import AVFoundation
import MediaPlayer
import Observation
import UIKit

/// Toca a narração de um livro, trecho por trecho, e diz qual palavra está sendo falada.
///
/// - Gera cada trecho só quando vai ser ouvido, a partir de onde a voz vai tocar,
///   e o próximo enquanto o atual toca, para a voz não parar na virada (objeto Narração).
/// - Tenta de novo sozinho até 3 vezes quando a geração falha.
/// - Troca de voz no meio do livro vale a partir do próximo capítulo.
/// - Timer de sono, e a voz continua com a tela bloqueada, com os controles do iOS.
@Observable
final class Tocador {
    enum Estado: Equatable { case parado, preparando, tocando, pausado, erro, fim }

    /// Opções do timer de sono (fluxo Ouvir um livro): 15, 30 e 45 minutos, 1 hora e fim do capítulo.
    enum Timer: Hashable {
        case minutos(Int)
        case fimDoCapitulo
    }

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
    /// A velocidade vale para todos os livros (fluxo Ouvir um livro), então fica guardada no aparelho.
    var velocidade: Float = Tocador.velocidadeGuardada {
        didSet {
            UserDefaults.standard.set(velocidade, forKey: "velocidade")
            player.defaultRate = velocidade
            if estado == .tocando { player.rate = velocidade }
            atualizarAgoraTocando()
        }
    }

    static var velocidadeGuardada: Float {
        let v = UserDefaults.standard.float(forKey: "velocidade")
        return velocidades.contains(v) ? v : 1
    }

    /// Avisa onde a voz está, para a biblioteca guardar a posição atual.
    var aoMudarPosicao: ((Posicao) -> Void)?
    /// Avisa que o livro acabou.
    var aoTerminar: (() -> Void)?
    /// Pergunta se este trecho pode ser gerado agora (5 minutos grátis, carência, teto do teste).
    var podeGerar: ((Trecho) -> Bool)?
    /// Avisa que a voz parou porque o próximo trecho não pode ser gerado.
    var aoNegarGeracao: (() -> Void)?
    /// Avisa quantos segundos de relógio a voz tocou (os 5 minutos contam o tempo em que a voz tocou).
    var aoTocar: ((TimeInterval) -> Void)?
    /// Avisa cada trecho novo gerado, com a duração do áudio.
    var aoGerar: ((AudioGerado) -> Void)?

    let livro: LivroLido
    private let voz: ServicoDeVoz
    /// A voz usada para gerar a narração agora.
    private(set) var idDaVoz: String
    /// Voz escolhida no meio de um capítulo: só entra no próximo capítulo (objeto Narração, atributo Voz).
    private var vozPendente: (id: String, capitulo: Int, trecho: Posicao?)?
    /// A voz que o botão de voz mostra: a escolhida, mesmo antes de começar a tocar.
    var idDaVozEscolhida: String { vozPendente?.id ?? idDaVoz }

    private(set) var timer: Timer?
    private(set) var fimDoTimer: Date?
    private var capituloDoTimer: Int?
    private var tarefaDoTimer: Task<Void, Never>?

    private let pasta: URL
    private let player = AVQueuePlayer()

    private struct Chave: Hashable {
        let inicio: Posicao
        let voz: String
    }
    private var audios: [Chave: AudioGerado] = [:]
    private var tarefas: [Chave: Task<AudioGerado, Error>] = [:]
    private var fila: Task<Void, Never>?
    private var chaveDoItem: [ObjectIdentifier: Chave] = [:]
    /// O último trecho posto na fila do tocador.
    private var ultimoNaFila: Trecho?
    private var preparandoProximo = false
    private var pedido = 0
    private var observadorDeTempo: Any?
    private var observadores: [NSObjectProtocol] = []
    private var ultimoPedidoComErro: Posicao?
    private var saltoPendente: TimeInterval?
    /// Onde a voz deve começar no primeiro play: a posição salva do livro.
    private var localInicial: Int
    /// Palavras acumuladas até cada parágrafo, para o progresso do capítulo.
    private let somas: [Int]
    private var ultimoTempo: TimeInterval?
    private var proximoNegado = false
    /// Parar quando a voz sair desta frase (fim dos 5 minutos grátis).
    private var pararDepoisDaFrase: (paragrafo: Int, fim: Int, entao: () -> Void)?

    init(livro: LivroLido, voz: ServicoDeVoz, idDaVoz: String, posicao: Posicao? = nil) {
        self.livro = livro
        self.voz = voz
        self.idDaVoz = idDaVoz
        // Posição atual (objeto Livro): começa no início do livro e depois continua de onde parou.
        let p = min(posicao?.paragrafo ?? 0, max(0, livro.texto.paragrafos.count - 1))
        self.paragrafoAtual = p
        self.localInicial = posicao?.paragrafo == p ? posicao?.deslocamento ?? 0 : 0
        var acumulado = 0
        self.somas = livro.texto.paragrafos.map { acumulado += TextoDoLivro.contarPalavras($0.texto); return acumulado }
        pasta = FileManager.default.temporaryDirectory.appendingPathComponent("narracoes/\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        player.actionAtItemEnd = .advance
        player.defaultRate = velocidade
        observarTempo()
        observarFimDosItens()
        observarInterrupcoes()
        configurarControlesDaTelaBloqueada()
    }

    var texto: TextoDoLivro { livro.texto }
    var capituloAtual: Int { texto.capitulo(em: Posicao(paragrafo: paragrafoAtual, deslocamento: 0)) }
    /// Onde a voz está agora, com a palavra dentro do parágrafo.
    var posicaoAtual: Posicao {
        Posicao(paragrafo: paragrafoAtual, deslocamento: palavraAtual?.paragrafo == paragrafoAtual ? palavraAtual?.local ?? 0 : 0)
    }

    // MARK: Comandos

    /// Leva a voz para um ponto do livro e começa a tocar. Se ali ainda não há narração,
    /// gera os 5 minutos a partir desse ponto, sem gerar o que ficou para trás.
    func tocar(aPartirDoParagrafo p: Int, local: Int = 0) {
        guard p >= 0, p < texto.paragrafos.count else { return }
        pedido += 1
        let meuPedido = pedido
        player.pause()
        player.removeAllItems()
        chaveDoItem = [:]
        ultimoNaFila = nil
        preparandoProximo = false
        proximoNegado = false
        paragrafoAtual = p
        palavraAtual = nil
        estado = .preparando
        ultimoPedidoComErro = nil
        let alvo = Posicao(paragrafo: p, deslocamento: local)
        Task {
            do {
                let vozDoTrecho = vozParaTrecho(comecandoEm: alvo)
                let audio: AudioGerado
                if let pronto = audioPronto(cobrindo: alvo, voz: vozDoTrecho) {
                    audio = pronto
                } else {
                    guard let trecho = CortadorDeTrechos.trecho(aPartirDe: alvo, em: texto) else { return }
                    if let pode = podeGerar, !pode(trecho) {
                        estado = .pausado
                        aoNegarGeracao?()
                        return
                    }
                    audio = try await audioComTentativas(trecho, voz: vozDoTrecho)
                }
                guard meuPedido == pedido else { return }
                enfileirar(audio)
                let inicio = audio.marcas.first { ($0.paragrafo, $0.local) >= (p, local) }?.inicio ?? 0
                await player.seek(to: CMTime(seconds: inicio, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                guard meuPedido == pedido else { return }
                comecar()
                prepararProximo()
            } catch {
                guard meuPedido == pedido else { return }
                ultimoPedidoComErro = alvo
                estado = .erro
            }
        }
    }

    func alternar() {
        switch estado {
        case .tocando: pausar()
        case .pausado: comecar()
        case .parado: comecarDaPosicaoSalva()
        case .fim: tocar(aPartirDoParagrafo: 0)
        case .erro: tentarDeNovo()
        case .preparando: break
        }
    }

    /// Primeiro play: a voz continua exatamente de onde o leitor parou.
    func comecarDaPosicaoSalva() {
        tocar(aPartirDoParagrafo: paragrafoAtual, local: localInicial)
    }

    func pausar() {
        guard estado == .tocando else { return }
        player.pause()
        estado = .pausado
        avisarPosicao()
        atualizarAgoraTocando()
    }

    private func avisarPosicao() {
        aoMudarPosicao?(posicaoAtual)
    }

    func tentarDeNovo() {
        let alvo = ultimoPedidoComErro ?? Posicao(paragrafo: paragrafoAtual, deslocamento: 0)
        tocar(aPartirDoParagrafo: alvo.paragrafo, local: alvo.deslocamento)
    }

    /// Volta ou avança 15 segundos dentro do trecho que está tocando.
    /// Toques seguidos somam a partir do último ponto pedido: dois toques são sempre 30 segundos.
    func pular(_ segundos: TimeInterval) {
        guard let item = player.currentItem else { return }
        let partida = saltoPendente ?? item.currentTime().seconds
        let alvo = min(max(0, partida + segundos), max(0, item.duration.seconds - 0.1))
        saltoPendente = alvo
        Task {
            await player.seek(to: CMTime(seconds: alvo, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            if saltoPendente == alvo { saltoPendente = nil }
            atualizar(tempo: alvo)
            atualizarAgoraTocando()
        }
    }

    /// Os 5 minutos grátis acabaram: a voz termina a frase que está falando e para.
    func pararNoFimDaFrase(entao: @escaping () -> Void) {
        guard pararDepoisDaFrase == nil else { return }
        guard let m = palavraAtual, m.paragrafo < texto.paragrafos.count else {
            pausar()
            entao()
            return
        }
        let p = texto.paragrafos[m.paragrafo]
        let fim = p.frases.first { NSLocationInRange(m.local, $0) }.map { $0.location + $0.length } ?? (m.local + m.tamanho)
        pararDepoisDaFrase = (m.paragrafo, fim, entao)
    }

    /// Depois que a assinatura libera, o que tinha sido negado pode ser gerado de novo.
    func liberarGeracao() {
        proximoNegado = false
        prepararProximo()
    }

    // MARK: Voz

    /// Troca a voz. Com o livro tocando, a voz nova entra no próximo capítulo, para a voz
    /// não mudar no meio de um capítulo; em livro de um capítulo só, no próximo trecho.
    /// Devolve `true` quando a troca fica para depois (o app mostra o aviso).
    @discardableResult
    func trocarVoz(_ id: String) -> Bool {
        guard id != idDaVozEscolhida else { return false }
        guard estado != .parado else {
            idDaVoz = id
            vozPendente = nil
            return false
        }
        if id == idDaVoz {
            vozPendente = nil
            return false
        }
        let trechoAtual = player.currentItem.flatMap { chaveDoItem[ObjectIdentifier($0)] }?.inicio
        vozPendente = (id, capituloAtual, trechoAtual)
        // O que já estava na fila depois do trecho atual foi gerado com a voz antiga: sai da fila.
        for item in player.items().dropFirst() {
            chaveDoItem[ObjectIdentifier(item)] = nil
            player.remove(item)
        }
        if let atual = trechoAtual, let a = audios.values.first(where: { $0.trecho.inicio == atual }) {
            ultimoNaFila = a.trecho
        }
        preparandoProximo = false
        prepararProximo()
        return true
    }

    /// A voz de um trecho novo. A voz escolhida no meio de um capítulo vale para
    /// trechos de outro capítulo (ou, em livro de um capítulo só, para outro trecho).
    private func vozParaTrecho(comecandoEm inicio: Posicao) -> String {
        guard let pendente = vozPendente else { return idDaVoz }
        let outro = texto.capitulos.count > 1
            ? texto.capitulo(em: inicio) != pendente.capitulo
            : inicio != pendente.trecho
        guard outro else { return idDaVoz }
        idDaVoz = pendente.id
        vozPendente = nil
        return idDaVoz
    }

    // MARK: Timer de sono

    func ligarTimer(_ opcao: Timer) {
        tarefaDoTimer?.cancel()
        timer = opcao
        switch opcao {
        case .minutos(let m):
            capituloDoTimer = nil
            let fim = Date.now.addingTimeInterval(TimeInterval(m * 60))
            fimDoTimer = fim
            tarefaDoTimer = Task { [weak self] in
                try? await Task.sleep(until: .now + .seconds(fim.timeIntervalSinceNow))
                guard !Task.isCancelled else { return }
                self?.pausar()
                self?.desligarTimer()
            }
        case .fimDoCapitulo:
            fimDoTimer = nil
            capituloDoTimer = capituloAtual
        }
    }

    func desligarTimer() {
        tarefaDoTimer?.cancel()
        tarefaDoTimer = nil
        timer = nil
        fimDoTimer = nil
        capituloDoTimer = nil
    }

    // MARK: Progresso do capítulo

    private func palavrasAntes(_ paragrafo: Int) -> Int { paragrafo > 0 && paragrafo <= somas.count ? somas[paragrafo - 1] : 0 }

    /// Palavras do capítulo atual: total, já ouvidas e que faltam (estimativa para a barra).
    var progressoDoCapitulo: (total: Int, ouvidas: Int) {
        let caps = texto.capitulos
        guard !caps.isEmpty else { return (0, 0) }
        let i = capituloAtual
        let inicio = caps[i].primeiroParagrafo
        let fim = i + 1 < caps.count ? caps[i + 1].primeiroParagrafo : texto.paragrafos.count
        let total = palavrasAntes(fim) - palavrasAntes(inicio)
        var ouvidas = palavrasAntes(paragrafoAtual) - palavrasAntes(inicio)
        if let m = palavraAtual, m.paragrafo == paragrafoAtual {
            ouvidas += TextoDoLivro.contarPalavras((texto.paragrafos[paragrafoAtual].texto as NSString).substring(to: min(m.local, (texto.paragrafos[paragrafoAtual].texto as NSString).length)))
        }
        return (max(total, 1), min(max(ouvidas, 0), total))
    }

    /// Leva a voz para um ponto do capítulo atual, pela fração da barra (arrastar a barra de progresso).
    func irPara(fracaoDoCapitulo f: Double) {
        let caps = texto.capitulos
        guard !caps.isEmpty else { return }
        let i = capituloAtual
        let inicio = caps[i].primeiroParagrafo
        let fim = i + 1 < caps.count ? caps[i + 1].primeiroParagrafo : texto.paragrafos.count
        let alvo = palavrasAntes(inicio) + Int(Double(palavrasAntes(fim) - palavrasAntes(inicio)) * min(max(f, 0), 1))
        let p = (inicio..<fim).first { somas[$0] > alvo } ?? max(inicio, fim - 1)
        tocar(aPartirDoParagrafo: p)
    }

    // MARK: Geração

    /// Um áudio já pronto que cobre esta posição, com esta voz. Parte do livro com narração
    /// pronta não é gerada de novo (objeto Narração, atributo Trecho).
    private func audioPronto(cobrindo p: Posicao, voz: String) -> AudioGerado? {
        audios.first { $0.key.voz == voz && $0.value.trecho.contem(p) }?.value
    }

    /// Gera um trecho, tentando de novo sozinho até 3 vezes (objeto Narração, ciclo de vida).
    private func audioComTentativas(_ trecho: Trecho, voz: String) async throws -> AudioGerado {
        var ultimoErro: Error?
        for tentativa in 1...3 {
            do { return try await audio(trecho, voz: voz) } catch {
                ultimoErro = error
                if tentativa < 3 { try? await Task.sleep(for: .seconds(1)) }
            }
        }
        throw ultimoErro!
    }

    /// As gerações acontecem uma de cada vez, em fila.
    private func audio(_ trecho: Trecho, voz idVoz: String) async throws -> AudioGerado {
        let chave = Chave(inicio: trecho.inicio, voz: idVoz)
        if let pronto = audios[chave] { return pronto }
        if let andando = tarefas[chave] { return try await andando.value }
        let anterior = fila
        let destino = pasta.appendingPathComponent("\(UUID().uuidString).caf")
        let (servico, texto) = (self.voz, livro.texto)
        let tarefa = Task {
            await anterior?.value
            return try await servico.gerar(trecho, de: texto, voz: idVoz, destino: destino)
        }
        tarefas[chave] = tarefa
        fila = Task { _ = try? await tarefa.value }
        do {
            let a = try await tarefa.value
            audios[chave] = a
            tarefas[chave] = nil
            aoGerar?(a)
            return a
        } catch {
            tarefas[chave] = nil
            throw error
        }
    }

    /// Gera o trecho seguinte enquanto o atual toca e já põe na fila do tocador.
    /// Só prepara um à frente: o que não vai ser ouvido não é gerado.
    private func prepararProximo() {
        guard !preparandoProximo, !proximoNegado, player.items().count <= 1,
              let ultimo = ultimoNaFila, let proximo = CortadorDeTrechos.proximo(depoisDe: ultimo, em: texto) else { return }
        if audioPronto(cobrindo: proximo.inicio, voz: idDaVozEscolhida) == nil, let pode = podeGerar, !pode(proximo) {
            proximoNegado = true
            return
        }
        preparandoProximo = true
        let meuPedido = pedido
        let vozDoTrecho = vozParaTrecho(comecandoEm: proximo.inicio)
        Task {
            defer { if meuPedido == pedido { preparandoProximo = false } }
            guard let audio = try? await audioComTentativas(proximo, voz: vozDoTrecho), meuPedido == pedido,
                  ultimoNaFila == ultimo else { return }
            enfileirar(audio)
            // A voz chegou ao fim do trecho antes de o próximo ficar pronto: continua agora.
            if estado == .preparando { comecar() }
        }
    }

    private func enfileirar(_ audio: AudioGerado) {
        let item = AVPlayerItem(url: audio.arquivo)
        item.audioTimePitchAlgorithm = .timeDomain // muda a velocidade sem mudar o tom da voz
        chaveDoItem[ObjectIdentifier(item)] = Chave(inicio: audio.trecho.inicio, voz: audio.voz)
        ultimoNaFila = audio.trecho
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
        guard let item = player.currentItem, let chave = chaveDoItem[ObjectIdentifier(item)],
              let audio = audios[chave], tempo.isFinite else { return }
        if estado == .tocando, let anterior = ultimoTempo, tempo > anterior, tempo - anterior < 1 {
            aoTocar?((tempo - anterior) / Double(max(velocidade, 0.25)))
        }
        ultimoTempo = tempo
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
        if let parar = pararDepoisDaFrase, marca.paragrafo != parar.paragrafo || marca.local >= parar.fim {
            // A voz para no fim da frase, nunca no meio de uma palavra (fluxo Começar a usar o Traça).
            pararDepoisDaFrase = nil
            pausar()
            parar.entao()
            return
        }
        if marca != palavraAtual { palavraAtual = marca }
        if marca.paragrafo != paragrafoAtual {
            paragrafoAtual = marca.paragrafo
            avisarPosicao()
            // Timer "fim do capítulo": para quando a voz entra no capítulo seguinte.
            if let c = capituloDoTimer, capituloAtual != c {
                pausar()
                desligarTimer()
            }
        }
        prepararProximo()
    }

    private func observarFimDosItens() {
        let o = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] aviso in
            MainActor.assumeIsolated {
                guard let self, let item = aviso.object as? AVPlayerItem,
                      let chave = self.chaveDoItem[ObjectIdentifier(item)],
                      let audio = self.audios[chave] else { return }
                self.chaveDoItem[ObjectIdentifier(item)] = nil
                if audio.trecho.ultimoParagrafo >= self.texto.paragrafos.count - 1 {
                    self.estado = .fim
                    self.desligarTimer()
                    self.aoTerminar?()
                } else if self.proximoNegado {
                    // O próximo trecho não pode ser gerado agora (5 minutos, carência ou teto do teste).
                    self.estado = .pausado
                    self.aoNegarGeracao?()
                } else if self.player.items().count <= 1 {
                    // O próximo trecho ainda não ficou pronto: "Preparando a voz".
                    self.estado = .preparando
                    self.prepararProximo()
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
        let caps = texto.capitulos
        if !caps.isEmpty, !caps[capituloAtual].titulo.isEmpty { info[MPMediaItemPropertyAlbumTitle] = caps[capituloAtual].titulo }
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
        if estado == .tocando || estado == .pausado { avisarPosicao() }
        pedido += 1
        desligarTimer()
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
