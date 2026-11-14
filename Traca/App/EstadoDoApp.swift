import Observation
import SwiftUI
import UserNotifications

/// As telas empilhadas por cima da tela inicial (Boas-vindas ou Biblioteca).
enum Rota: Hashable {
    case escolherVoz(UUID)
    case player
    case conta
}

/// O painel de entrar que sobe da base.
enum PainelDeEntrar: Equatable {
    /// CMC-007: os 5 minutos acabaram (ou tentou importar outro livro antes do login).
    case fimDosMinutos(titulo: String)
    /// CMC-010: "Já tenho conta".
    case jaTenhoConta
}

/// O que o leitor pode fazer agora, pelo estado da Assinatura (permissões do objeto Livro).
enum Acesso: Equatable {
    case antesDoTeste
    case liberado(emTeste: Bool)
    case carencia
    case expirada
}

/// Aviso curto que aparece por cima de qualquer tela e some sozinho.
enum AvisoGeral: Equatable {
    case assinaturaAtiva
    case assinaturaRestaurada

    var texto: String {
        switch self {
        case .assinaturaAtiva: "Pronto! Sua assinatura está ativa."
        case .assinaturaRestaurada: "Sua assinatura foi restaurada."
        }
    }
}

/// O estado do app inteiro: conta, assinatura, biblioteca, o livro que está tocando e a navegação.
@Observable
final class EstadoDoApp {
    let contas = Contas()
    let loja = Loja()
    let rede = Rede()
    private(set) var biblioteca: Biblioteca
    var caminho: [Rota] = []
    private(set) var tocador: Tocador?
    private(set) var livroTocando: UUID?
    /// Aviso "Este livro já está na sua biblioteca." por cima do player (IMP-004).
    var avisoNoPlayer: AvisoDaBiblioteca?
    var painelDeEntrar: PainelDeEntrar?
    var mostrandoAssinar = false
    var avisoGeral: AvisoGeral?
    /// O player mostra "Não conseguimos renovar sua assinatura" (ASS-003) quando a carência impede gerar.
    var avisoDeCarencia = false
    /// O player mostra o aviso do teto de 3 horas do teste.
    var avisoDoTeto = false
    private(set) var minutosGratis = MinutosGratis.carregar()

    /// Teto de narração gerada no teste inteiro (objeto Assinatura).
    static let tetoDoTeste: TimeInterval = 3 * 60 * 60

    init() {
        let contas = self.contas
        biblioteca = contas.atual.map { Biblioteca(pasta: Contas.pasta(de: $0)) } ?? Biblioteca()
        loja.conta = contas.atual?.id
        Task { await loja.carregarProdutos() }
    }

    /// A voz escolhida vale para os próximos livros também (fluxo Ouvir um livro).
    static var idDaVozEscolhida: String? {
        get { UserDefaults.standard.string(forKey: "voz") }
        set { UserDefaults.standard.set(newValue, forKey: "voz") }
    }

    var livroDoTocador: LivroGuardado? {
        biblioteca.livros.first { $0.id == livroTocando }
    }

    // MARK: Acesso

    var acesso: Acesso {
        guard contas.atual != nil else { return .antesDoTeste }
        switch loja.situacao {
        case .semAssinatura: return .antesDoTeste
        case .emTeste: return .liberado(emTeste: true)
        case .ativa: return .liberado(emTeste: false)
        case .carencia: return .carencia
        case .expirada: return .expirada
        }
    }

    /// Quanto já foi gerado de narração no teste desta conta.
    private var geradoNoTeste: TimeInterval {
        get { contas.atual.map { UserDefaults.standard.double(forKey: "geradoNoTeste-\($0.id)") } ?? 0 }
        set { if let c = contas.atual { UserDefaults.standard.set(newValue, forKey: "geradoNoTeste-\(c.id)") } }
    }

    /// Se um trecho pode ser gerado agora (permissões do objeto Narração).
    private func podeGerar(_ trecho: Trecho, livro: LivroGuardado) -> Bool {
        switch acesso {
        case .liberado(let emTeste):
            if emTeste, geradoNoTeste >= Self.tetoDoTeste {
                avisoDoTeto = true
                return false
            }
            return true
        case .carencia:
            avisoDeCarencia = true
            return false
        case .expirada:
            return false
        case .antesDoTeste:
            // Só até 5 minutos de voz do livro importado (objeto Narração, decisão de 13/11/2026).
            let doLivro = minutosGratis.livro == nil || minutosGratis.livro == livro.impressaoDigital
            return doLivro && !minutosGratis.acabaram && minutosGratis.gerados < MinutosGratis.limite
        }
    }

    /// O que o leitor vê quando bate num limite antes de assinar.
    func pedirParaContinuar() {
        if contas.atual == nil {
            painelDeEntrar = .fimDosMinutos(titulo: livroDoTocador?.titulo ?? biblioteca.livros.first?.titulo ?? "")
        } else {
            mostrandoAssinar = true
        }
    }

    // MARK: Abrir e importar

    /// Abre o player de um livro, na posição salva. Se outro livro estava tocando, ele para.
    func abrir(_ livro: LivroGuardado, comAviso aviso: AvisoDaBiblioteca? = nil) {
        // Assinatura expirada: ouvir leva ao paywall (fluxo Ouvir um livro, critérios de aceite).
        if acesso == .expirada {
            mostrandoAssinar = true
            return
        }
        if livroTocando != livro.id {
            tocador?.encerrar()
            guard let lido = biblioteca.lido(livro) else {
                biblioteca.aviso = .erro(.corrompido)
                return
            }
            let voz = VozDoIPhone()
            let opcoes = voz.vozes
            let id = opcoes.first { $0.id == Self.idDaVozEscolhida }?.id ?? opcoes.first?.id ?? ""
            let novo = Tocador(livro: lido, voz: voz, idDaVoz: id, posicao: livro.terminado ? .inicio : livro.posicao)
            let livroID = livro.id
            let texto = lido.texto
            novo.aoMudarPosicao = { [weak self] posicao in
                self?.biblioteca.salvarPosicao(livroID, posicao, capitulo: texto.capitulo(em: posicao))
            }
            novo.aoTerminar = { [weak self] in self?.biblioteca.marcarTerminado(livroID) }
            novo.podeGerar = { [weak self] trecho in
                guard let self, let l = self.biblioteca.livros.first(where: { $0.id == livroID }) else { return false }
                return self.podeGerar(trecho, livro: l)
            }
            novo.aoNegarGeracao = { [weak self] in
                guard let self else { return }
                if self.acesso == .antesDoTeste || self.acesso == .expirada { self.pedirParaContinuar() }
            }
            novo.aoGerar = { [weak self] audio in self?.registrarGeracao(audio, livro: livroID) }
            novo.aoTocar = { [weak self] segundos in self?.registrarTempoTocado(segundos) }
            tocador = novo
            livroTocando = livro.id
        }
        biblioteca.registrarAbertura(livro.id)
        avisoNoPlayer = aviso
        caminho = [.player]
    }

    private func registrarGeracao(_ audio: AudioGerado, livro: UUID) {
        switch acesso {
        case .antesDoTeste:
            minutosGratis.gerados += audio.duracao
            if minutosGratis.livro == nil { minutosGratis.livro = biblioteca.livros.first { $0.id == livro }?.impressaoDigital }
            minutosGratis.salvar()
        case .liberado(emTeste: true):
            geradoNoTeste += audio.duracao
        default: break
        }
    }

    /// Os 5 minutos contam o tempo em que a voz tocou. Quando acabam, a voz para no fim da frase
    /// e aparece Fim dos 5 minutos · Entrar.
    private func registrarTempoTocado(_ segundos: TimeInterval) {
        guard acesso == .antesDoTeste, !minutosGratis.acabaram else { return }
        minutosGratis.tocados += segundos
        if minutosGratis.acabaram {
            minutosGratis.salvar()
            tocador?.pararNoFimDaFrase { [weak self] in self?.pedirParaContinuar() }
        } else if Int(minutosGratis.tocados) % 5 == 0 {
            minutosGratis.salvar()
        }
    }

    /// Importa arquivos vindos do botão de importar ou do "Compartilhar" de outro app.
    /// O primeiro livro do leitor leva a Escolher a voz; os outros só entram na biblioteca.
    func importar(_ urls: [URL]) async {
        // Antes do teste, só um livro pode ser importado; com a assinatura expirada, nenhum.
        if acesso == .expirada {
            mostrandoAssinar = true
            return
        }
        if acesso == .antesDoTeste, !biblioteca.livros.isEmpty {
            pedirParaContinuar()
            return
        }
        let primeiro = !biblioteca.jaImportou
        guard let livro = await biblioteca.importar(acesso == .antesDoTeste ? Array(urls.prefix(1)) : urls) else { return }
        if biblioteca.aviso == .repetido {
            biblioteca.aviso = nil
            abrir(livro, comAviso: .repetido)
        } else if primeiro {
            caminho = [.escolherVoz(livro.id)]
        }
    }

    func excluir(_ livro: LivroGuardado) {
        if livroTocando == livro.id { pararTocador() }
        biblioteca.excluir(livro.id)
    }

    private func pararTocador() {
        tocador?.encerrar()
        tocador = nil
        livroTocando = nil
    }

    // MARK: Conta

    /// Entra com a Apple ou o Google. No primeiro login, o livro importado antes passa para a conta.
    func entrar(com provedor: Conta.Provedor) {
        let painel = painelDeEntrar
        let conta = contas.entrar(com: provedor)
        let daConta = Biblioteca(pasta: Contas.pasta(de: conta))
        daConta.incorporar(biblioteca)
        let tocandoAgora = livroTocando
        pararTocador()
        biblioteca = daConta
        loja.conta = conta.id
        painelDeEntrar = nil
        Task {
            await loja.atualizar()
            // Fim dos 5 minutos: depois de entrar, Começar o teste. "Já tenho conta": a Biblioteca da conta.
            if case .fimDosMinutos = painel {
                if let id = tocandoAgora, let livro = biblioteca.livros.first(where: { $0.id == id }) ?? biblioteca.livros.first {
                    abrir(livro)
                }
                if acesso == .antesDoTeste { mostrandoAssinar = true }
            } else {
                caminho = []
            }
        }
    }

    /// Sair encerra a conta neste aparelho, sem confirmação, e volta para Boas-vindas.
    func sair() {
        pararTocador()
        contas.sair()
        loja.conta = nil
        biblioteca = Biblioteca()
        caminho = []
    }

    /// Excluir a conta. Sem internet, nada é apagado (fluxo Gerenciar a conta).
    func excluirConta() async -> Bool {
        guard rede.conectada else { return false }
        try? await Task.sleep(for: .seconds(1.5))
        pararTocador()
        contas.excluir()
        loja.conta = nil
        biblioteca = Biblioteca()
        caminho = []
        return true
    }

    // MARK: Assinatura

    /// Depois da compra, as ações bloqueadas são liberadas na hora, sem reiniciar o app.
    func assinaturaMudou() {
        avisoDeCarencia = false
        avisoDoTeto = false
        tocador?.liberarGeracao()
    }

    /// O lembrete do dia 5 do teste, se o leitor permitiu notificações (fluxo Assinar o Traça).
    func agendarLembreteDoTeste() {
        guard case .emTeste(_, let fim) = loja.situacao, let fim else { return }
        let conteudo = UNMutableNotificationContent()
        conteudo.body = "Seu teste do Traça acaba em 2 dias. Para continuar ouvindo, não precisa fazer nada."
        let quando = fim.addingTimeInterval(-2 * 24 * 60 * 60)
        guard quando > .now else { return }
        let gatilho = UNTimeIntervalNotificationTrigger(timeInterval: quando.timeIntervalSinceNow, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "lembrete-do-teste", content: conteudo, trigger: gatilho))
    }

    func mostrar(_ aviso: AvisoGeral) {
        avisoGeral = aviso
        Task {
            try? await Task.sleep(for: .seconds(3))
            if avisoGeral == aviso { avisoGeral = nil }
        }
    }
}
