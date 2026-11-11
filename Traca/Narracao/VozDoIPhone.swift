import AVFoundation

/// Voz provisória da Fase 0: a voz do próprio iPhone (AVSpeechSynthesizer).
///
/// Em vez de falar direto no alto-falante, ela grava o áudio num arquivo e anota o tempo
/// de cada palavra, do mesmo jeito que a Inworld vai fazer. Assim o tocador, o destaque
/// das palavras e a tela bloqueada funcionam igual com as duas vozes.
///
/// O tempo de cada palavra vem do aviso "vou falar esta palavra" que a voz dá enquanto grava:
/// a palavra começa no ponto do áudio que já tinha sido gravado naquele momento.
/// É uma aproximação boa para a voz provisória; a Inworld devolve o tempo exato.
final class VozDoIPhone: ServicoDeVoz {
    private let sintetizador = AVSpeechSynthesizer()

    var vozes: [OpcaoDeVoz] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == "pt-BR" }
            .sorted { $0.quality.rawValue > $1.quality.rawValue }
            .map { OpcaoDeVoz(id: $0.identifier, nome: $0.name) }
    }

    enum Erro: Error { case semAudio }

    func gerar(_ trecho: Trecho, de texto: TextoDoLivro, voz: String, destino: URL) async throws -> AudioGerado {
        let (fala, inicios) = Self.montarTexto(trecho, de: texto)
        let enunciado = AVSpeechUtterance(string: fala)
        enunciado.voice = AVSpeechSynthesisVoice(identifier: voz) ?? AVSpeechSynthesisVoice(language: "pt-BR")
        enunciado.prefersAssistiveTechnologySettings = false

        try? FileManager.default.removeItem(at: destino)
        let coletor = Coletor(destino: destino)
        sintetizador.delegate = coletor
        defer { sintetizador.delegate = nil }

        try await withCheckedThrowingContinuation { (fim: CheckedContinuation<Void, Error>) in
            coletor.aoTerminar = { erro in
                if let erro { fim.resume(throwing: erro) } else { fim.resume(returning: ()) }
            }
            sintetizador.write(enunciado) { buffer in coletor.receber(buffer) }
        }

        let (amostras, taxa, brutas) = coletor.resultado()
        guard amostras > 0 else { throw Erro.semAudio }
        let marcas = brutas.map { b -> MarcaDeTempo in
            let (p, local) = Self.localizar(b.intervalo.location, em: inicios)
            return MarcaDeTempo(paragrafo: p, local: local, tamanho: b.intervalo.length, inicio: Double(b.amostra) / taxa)
        }
        return AudioGerado(trecho: trecho.indice, voz: voz, arquivo: destino,
                           duracao: Double(amostras) / taxa, marcas: marcas.sorted { $0.inicio < $1.inicio })
    }
}

/// Recebe os pedaços de áudio e os avisos de palavra, que chegam por caminhos diferentes,
/// e grava tudo num arquivo. A trava evita que os dois caminhos se atropelem.
private nonisolated final class Coletor: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let trava = NSLock()
    private let destino: URL
    private var arquivo: AVAudioFile?
    private var amostras: AVAudioFramePosition = 0
    private var taxa: Double = 22_050
    private var palavras: [(intervalo: NSRange, amostra: AVAudioFramePosition)] = []
    private var terminou = false
    var aoTerminar: ((Error?) -> Void)?

    init(destino: URL) { self.destino = destino }

    func receber(_ buffer: AVAudioBuffer) {
        guard let pcm = buffer as? AVAudioPCMBuffer else { return }
        trava.lock()
        defer { trava.unlock() }
        guard !terminou else { return }
        if pcm.frameLength == 0 {
            // Pedaço vazio é o aviso de que a voz terminou.
            terminar(nil)
            return
        }
        do {
            if arquivo == nil {
                taxa = pcm.format.sampleRate
                arquivo = try AVAudioFile(forWriting: destino, settings: pcm.format.settings,
                                          commonFormat: pcm.format.commonFormat, interleaved: pcm.format.isInterleaved)
            }
            try arquivo?.write(from: pcm)
            amostras += AVAudioFramePosition(pcm.frameLength)
        } catch {
            terminar(error)
        }
    }

    func speechSynthesizer(_ s: AVSpeechSynthesizer, willSpeakRangeOfSpeechString intervalo: NSRange, utterance: AVSpeechUtterance) {
        trava.lock()
        palavras.append((intervalo, amostras))
        trava.unlock()
    }

    func resultado() -> (AVAudioFramePosition, Double, [(intervalo: NSRange, amostra: AVAudioFramePosition)]) {
        trava.lock()
        defer { trava.unlock() }
        return (amostras, taxa, palavras)
    }

    private func terminar(_ erro: Error?) {
        terminou = true
        arquivo = nil // fecha o arquivo
        let aviso = aoTerminar
        aoTerminar = nil
        aviso?(erro)
    }
}
