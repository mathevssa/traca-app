import Observation
import SwiftUI

/// As telas empilhadas por cima da tela inicial (Boas-vindas ou Biblioteca).
enum Rota: Hashable {
    case escolherVoz(UUID)
    case player
}

/// O estado do app inteiro: a biblioteca, o livro que está tocando e a navegação.
@Observable
final class EstadoDoApp {
    let biblioteca = Biblioteca()
    var caminho: [Rota] = []
    private(set) var tocador: Tocador?
    private(set) var livroTocando: UUID?
    /// Aviso "Este livro já está na sua biblioteca." por cima do player (IMP-004).
    var avisoNoPlayer: AvisoDaBiblioteca?

    /// A voz escolhida vale para os próximos livros também (fluxo Ouvir um livro).
    static var idDaVozEscolhida: String? {
        get { UserDefaults.standard.string(forKey: "voz") }
        set { UserDefaults.standard.set(newValue, forKey: "voz") }
    }

    var livroDoTocador: LivroGuardado? {
        biblioteca.livros.first { $0.id == livroTocando }
    }

    /// Abre o player de um livro, na posição salva. Se outro livro estava tocando, ele para.
    func abrir(_ livro: LivroGuardado, comAviso aviso: AvisoDaBiblioteca? = nil) {
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
            tocador = novo
            livroTocando = livro.id
        }
        biblioteca.registrarAbertura(livro.id)
        avisoNoPlayer = aviso
        caminho = [.player]
    }

    /// Importa arquivos vindos do botão de importar ou do "Compartilhar" de outro app.
    /// O primeiro livro do leitor leva a Escolher a voz; os outros só entram na biblioteca.
    func importar(_ urls: [URL]) async {
        let primeiro = !biblioteca.jaImportou
        guard let livro = await biblioteca.importar(urls) else { return }
        if biblioteca.aviso == .repetido {
            biblioteca.aviso = nil
            abrir(livro, comAviso: .repetido)
        } else if primeiro {
            caminho = [.escolherVoz(livro.id)]
        }
    }

    func excluir(_ livro: LivroGuardado) {
        if livroTocando == livro.id {
            tocador?.encerrar()
            tocador = nil
            livroTocando = nil
        }
        biblioteca.excluir(livro.id)
    }
}
