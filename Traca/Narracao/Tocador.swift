import AVFoundation
import MediaPlayer
import Observation
import UIKit

/// Toca a narração de um livro, trecho por trecho, e diz qual palavra está sendo falada.
///
/// - Gera cada trecho só quando vai ser ouvido, e o próximo enquanto o atual toca,
///   para a voz não parar na virada (objeto Narração).
/// - Tenta de novo sozinho até 3 vezes quando a geração falha.
/// - Continua tocando com a tela bloqueada, com os controles do iOS na tela bloqueada e nos fones.
@Observable
final class Tocador {
    enum Estado: Equatable { case parado, preparando, tocando, pausado, erro, fim }

    private(set) var estado: Estado = .parado
    /// A palavra que a voz está falando agora.
    private(set) var palavraAtual: MarcaDeTempo?
    /// O parágrafo onde a voz está. É a posição atual do livro.
    private(set) var paragrafoAtual: Int
    /// Tempo dentro do trecho que está tocando, e a duração dele.
    private(set) var tempoNoTrecho: TimeInterval = 0
    private(set) var duracaoDoTrecho: TimeInterval = 0

    /// Velocidade de 0,75x a 2x, em passos de 0,25x (fluxo Ouvir um livro).
    static let velocidades: [Float] = [0.75, 1, 1.25, 1.5, 1.75, 2]

    /// Como a velocidade aparece na tela: "0,75x", "1x", "1,25x", "1,5x", "2x".
    static func rotulo(_ v: Float) -> String {
        var t = String(format: "%.2f", v)
        while t.hasSuffix("0") { t.removeLast() }
        if t.hasSuffix(".") { t.removeLast() }
        return t.replacingOccurrences(of: ".", with: ",") + "x"
    }
    var velocidade: Float = 1 {
        didSet {
            player.defaultRate = velocidade
            if estado == .tocando { player.rate = velocidade }
            atualizarAgoraTocando()
        }
    }

    let livro: LivroLido
    let trechos: [Trecho]
    private let voz: ServicoDeVoz
    private let idDaVoz: String
    private let pasta: URL
    private let player = AVQueuePlayer()
    private var audios: [Int: AudioGerado] = [:]
    private var tarefas: [Int: Task<AudioGerado, Error>] = [:]
    private var fila: Task<Void, Never>?
    private var trechoDoItem: [ObjectIdentifier: Int] = [:]
    private var enfileirados: Set<Int> = []
    private var pedido = 0
    private var observadorDeTempo: Any?
    private var observadores: [NSObjectProtocol] = []
    private var ultimoPedidoComErro: (paragrafo: Int, local: Int)?

    init(livro: LivroLido, voz: ServicoDeVoz, idDaVoz: String) {
        self.livro = livro
        self.trechos = CortadorDeTrechos.cortar(livro.texto)
        self.voz = voz
        self.idDaVoz = idDaVoz
        self.paragrafoAtual = livro.texto.paragrafos.firstIndex { $0.tipo == .corpo } ?? 0
        pasta = FileManager.default.temporaryDirectory.appendingPathComponent("narracoes/\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        player.actionAtItemEnd = .advance
        observarTempo()
        observarFimDosItens()
        observarInterrupcoes()
        configurarControlesDaTelaBloqueada()
    }

    var trechoAtual: Trecho? { CortadorDeTrechos.trecho(doParagrafo: paragrafoAtual, em: trechos) }

    // MARK: Comandos

    /// Leva a voz para o começo de um parágrafo (ou de uma palavra dentro dele) e começa a tocar.
    func tocar(aPartirDoParagrafo p: Int, local: Int = 0) {
        guard let trecho = CortadorDeTrechos.trecho(doParagrafo: p, em: trechos) else { return }
        pedido += 1
        let meuPedido = pedido
        player.pause()
        player.removeAllItems()
        trechoDoItem = [:]
        enfileirados = []
        paragrafoAtual = p
        palavraAtual = nil
        estado = .preparando
        ultimoPedidoComErro = nil
        Task {
            do {
                let audio = try await audioComTentativas(trecho)
                guard meuPedido == pedido else { return }
                enfileirar(audio)
                let inicio = audio.marcas.first { ($0.paragrafo, $0.local) >= (p, local) }?.inicio ?? 0
                await player.seek(to: CMTime(seconds: inicio, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                guard meuPedido == pedido else { return }
                comecar()
                prepararProximo(depoisDe: trecho.indice)
            } catch {
                guard meuPedido == pedido else { return }
                ultimoPedidoComErro = (p, local)
                estado = .erro
            }
        }
    }

    func alternar() {
        switch estado {
        case .tocando: pausar()
        case .pausado: comecar()
        case .parado, .fim: tocar(aPartirDoParagrafo: estado == .fim ? 0 : paragrafoAtual)
        case .erro: tentarDeNovo()
        case .preparando: break
        }
    }

    func pausar() {
        guard estado == .tocando else { return }
        player.pause()
        estado = .pausado
        atualizarAgoraTocando()
    }

    func tentarDeNovo() {
        let alvo = ultimoPedidoComErro ?? (paragrafoAtual, 0)
        tocar(aPartirDoParagrafo: alvo.paragrafo, local: alvo.local)
    }

    /// Volta ou avança 15 segundos dentro do trecho que está tocando.
    func pular(_ segundos: TimeInterval) {
        guard let item = player.currentItem else { return }
        let alvo = min(max(0, item.currentTime().seconds + segundos), max(0, item.duration.seconds - 0.1))
        Task {
            await player.seek(to: CMTime(seconds: alvo, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            atualizarAgoraTocando()
        }
    }

    // MARK: Geração

    /// Gera um trecho, tentando de novo sozinho até 3 vezes (objeto Narração, ciclo de vida).
    private func audioComTentativas(_ trecho: Trecho) async throws -> AudioGerado {
        var ultimoErro: Error?
        for tentativa in 1...3 {
            do { return try await audio(trecho) } catch {
                ultimoErro = error
                if tentativa < 3 { try? await Task.sleep(for: .seconds(1)) }
            }
        }
        throw ultimoErro!
    }

    /// Cada trecho é gerado uma vez só. As gerações acontecem uma de cada vez, em fila.
    private func audio(_ trecho: Trecho) async throws -> AudioGerado {
        if let pronto = audios[trecho.indice] { return pronto }
        if let andando = tarefas[trecho.indice] { return try await andando.value }
        let anterior = fila
        let destino = pasta.appendingPathComponent("trecho-\(trecho.indice).caf")
        let (voz, texto, id) = (self.voz, livro.texto, idDaVoz)
        let tarefa = Task {
            await anterior?.value
            return try await voz.gerar(trecho, de: texto, voz: id, destino: destino)
        }
        tarefas[trecho.indice] = tarefa
        fila = Task { _ = try? await tarefa.value }
        do {
            let a = try await tarefa.value
            audios[trecho.indice] = a
            tarefas[trecho.indice] = nil
            return a
        } catch {
            tarefas[trecho.indice] = nil
            throw error
        }
    }

    /// Gera o próximo trecho enquanto o atual toca e já põe na fila do tocador.
    private func prepararProximo(depoisDe indice: Int) {
        let proximo = indice + 1
        guard proximo < trechos.count, !enfileirados.contains(proximo) else { return }
        let meuPedido = pedido
        Task {
            guard let audio = try? await audioComTentativas(trechos[proximo]), meuPedido == pedido,
                  !enfileirados.contains(proximo) else { return }
            enfileirar(audio)
            // A voz chegou ao fim do trecho antes de o próximo ficar pronto: continua agora.
            if estado == .preparando { comecar() }
        }
    }

    private func enfileirar(_ audio: AudioGerado) {
        let item = AVPlayerItem(url: audio.arquivo)
        item.audioTimePitchAlgorithm = .timeDomain // muda a velocidade sem mudar o tom da voz
        trechoDoItem[ObjectIdentifier(item)] = audio.trecho
        enfileirados.insert(audio.trecho)
        player.insert(item, after: player.items().last)
    }

    // MARK: Tocar

    private func comecar() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        player.playImmediately(atRate: velocidade)
        estado = .tocando
        atualizarAgoraTocando()
    }

    private func observarTempo() {
        observadorDeTempo = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] tempo in
            MainActor.assumeIsolated { self?.atualizar(tempo: tempo.seconds) }
        }
    }

    /// Acha a palavra que está sendo falada agora, pelo tempo do áudio.
    private func atualizar(tempo: TimeInterval) {
        guard let item = player.currentItem, let indice = trechoDoItem[ObjectIdentifier(item)],
              let audio = audios[indice], tempo.isFinite else { return }
        tempoNoTrecho = tempo
        duracaoDoTrecho = audio.duracao
        let marcas = audio.marcas
        var baixo = 0, alto = marcas.count - 1, achada = -1
        while baixo <= alto {
            let meio = (baixo + alto) / 2
            if marcas[meio].inicio <= tempo { achada = meio; baixo = meio + 1 } else { alto = meio - 1 }
        }
        guard achada >= 0 else { return }
        let marca = marcas[achada]
        if marca != palavraAtual { palavraAtual = marca }
        if marca.paragrafo != paragrafoAtual { paragrafoAtual = marca.paragrafo }
        prepararProximo(depoisDe: indice)
    }

    private func observarFimDosItens() {
        let o = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] aviso in
            MainActor.assumeIsolated {
                guard let self, let item = aviso.object as? AVPlayerItem,
                      let indice = self.trechoDoItem[ObjectIdentifier(item)] else { return }
                self.trechoDoItem[ObjectIdentifier(item)] = nil
                if indice == self.trechos.count - 1 {
                    self.estado = .fim
                } else if !self.enfileirados.contains(indice + 1) {
                    // O próximo trecho ainda não ficou pronto: "Preparando a voz".
                    self.estado = .preparando
                    self.prepararProximo(depoisDe: indice)
                }
            }
        }
        observadores.append(o)
    }

    /// Ligação ou alarme pausam a voz; quando acabam, ela volta se o iOS disser que pode.
    private func observarInterrupcoes() {
        let o = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] aviso in
            MainActor.assumeIsolated {
                guard let self, let info = aviso.userInfo,
                      let tipo = (info[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init) else { return }
                if tipo == .began {
                    self.pausar()
                } else if let op = info[AVAudioSessionInterruptionOptionKey] as? UInt,
                          AVAudioSession.InterruptionOptions(rawValue: op).contains(.shouldResume), self.estado == .pausado {
                    self.comecar()
                }
            }
        }
        observadores.append(o)
    }

    // MARK: Tela bloqueada

    private func configurarControlesDaTelaBloqueada() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { if self?.estado != .tocando { self?.alternar() } }
            return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.pausar() }
            return .success
        }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.alternar() }
            return .success
        }
        c.skipForwardCommand.preferredIntervals = [15]
        c.skipForwardCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.pular(15) }
            return .success
        }
        c.skipBackwardCommand.preferredIntervals = [15]
        c.skipBackwardCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.pular(-15) }
            return .success
        }
    }

    private func atualizarAgoraTocando() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: livro.titulo ?? "",
            MPNowPlayingInfoPropertyPlaybackRate: estado == .tocando ? Double(velocidade) : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(velocidade),
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let autor = livro.autor { info[MPMediaItemPropertyArtist] = autor }
        let caps = livro.texto.capitulos
        let cap = caps[livro.texto.capitulo(em: Posicao(paragrafo: paragrafoAtual, deslocamento: 0))]
        if !cap.titulo.isEmpty { info[MPMediaItemPropertyAlbumTitle] = cap.titulo }
        if let item = player.currentItem {
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = item.currentTime().seconds
            if item.duration.isNumeric { info[MPMediaItemPropertyPlaybackDuration] = item.duration.seconds }
        }
        if let dados = livro.capa, let imagem = UIImage(data: dados) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: imagem.size) { _ in imagem }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func encerrar() {
        pedido += 1
        player.pause()
        player.removeAllItems()
        if let o = observadorDeTempo { player.removeTimeObserver(o) }
        observadores.forEach(NotificationCenter.default.removeObserver)
        let c = MPRemoteCommandCenter.shared()
        [c.playCommand, c.pauseCommand, c.togglePlayPauseCommand, c.skipForwardCommand, c.skipBackwardCommand].forEach { $0.removeTarget(nil) }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? FileManager.default.removeItem(at: pasta)
    }
}
