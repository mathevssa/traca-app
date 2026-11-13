import CryptoKit
import Foundation
import Observation
import UIKit

/// Um livro guardado na biblioteca do aparelho (objeto Livro do Atlas).
/// O texto já lido fica num arquivo à parte, para a biblioteca abrir rápido sem ler os livros de novo.
nonisolated struct LivroGuardado: Codable, Identifiable, Hashable {
    let id: UUID
    var titulo: String
    var autor: String?
    var formato: Formato
    /// O nome do arquivo que o leitor escolheu, como "o-cortico.epub".
    var nomeDoArquivo: String
    var temCapa: Bool
    /// Identifica o conteúdo do arquivo, para reconhecer o mesmo livro importado de novo.
    var impressaoDigital: String
    var importadoEm: Date
    var abertoEm: Date?
    var posicao: Posicao
    var totalDePalavras: Int
    var palavrasRestantes: Int
    /// Índice do capítulo onde a posição está.
    var capituloAtual: Int
    var terminado: Bool

    /// Ordem da biblioteca: pela última abertura; livro nunca aberto usa a data de importação.
    var dataDeOrdem: Date { abertoEm ?? importadoEm }
}

/// Um arquivo que está sendo importado agora (card "Importando" da biblioteca).
struct Importacao: Identifiable, Hashable {
    let id = UUID()
    let nomeDoArquivo: String
}

/// Avisos da biblioteca (fluxo Importar e excluir livros, Mensagens).
enum AvisoDaBiblioteca: Equatable {
    case erro(ErroDeLeitura)
    case repetido

    var texto: String {
        switch self {
        case .repetido: "Este livro já está na sua biblioteca."
        case .erro(.drm): "Este livro tem proteção contra cópia (DRM) e não abre fora da loja onde foi comprado. Tente um arquivo sem proteção."
        case .erro(.corrompido): "Não conseguimos abrir este arquivo. Ele pode estar danificado. Tente baixar de novo."
        case .erro(.formatoNaoAceito): "O Traça ainda não abre esse tipo de arquivo. Ele abre EPUB, PDF, MOBI, AZW3, FB2, TXT e RTF."
        }
    }
}

/// A biblioteca do aparelho: importa, guarda, ordena e exclui livros, e lembra onde o leitor parou.
@Observable
final class Biblioteca {
    private(set) var livros: [LivroGuardado] = []
    private(set) var importando: [Importacao] = []
    /// Aviso de erro ou de livro repetido. Fica na tela até o leitor fechar ou sair da biblioteca.
    var aviso: AvisoDaBiblioteca?

    /// Se o leitor já importou algum livro alguma vez. Antes disso, o app abre em Boas-vindas.
    var jaImportou: Bool {
        get { UserDefaults.standard.bool(forKey: "jaImportou") || !livros.isEmpty }
        set { UserDefaults.standard.set(newValue, forKey: "jaImportou") }
    }

    private let pasta: URL
    private var capas: [UUID: UIImage] = [:]
    /// Palavras acumuladas até cada parágrafo, para calcular o "faltam" sem ler o livro de novo.
    private var somas: [UUID: [Int]] = [:]

    init(pasta: URL = URL.applicationSupportDirectory.appendingPathComponent("Biblioteca", isDirectory: true)) {
        self.pasta = pasta
        try? FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        if let dados = try? Data(contentsOf: indice),
           let lista = try? JSONDecoder().decode([LivroGuardado].self, from: dados) {
            livros = lista
        }
        ordenar()
    }

    private var indice: URL { pasta.appendingPathComponent("indice.json") }
    private func pasta(de id: UUID) -> URL { pasta.appendingPathComponent(id.uuidString, isDirectory: true) }

    // MARK: Importar

    /// Importa um ou mais arquivos. Devolve o livro a abrir: o importado (quando é um só)
    /// ou o que já estava na biblioteca, se o arquivo for repetido.
    @discardableResult
    func importar(_ urls: [URL]) async -> LivroGuardado? {
        var aAbrir: LivroGuardado?
        for url in urls {
            let resultado = await importar(url)
            if urls.count == 1 { aAbrir = resultado }
        }
        return aAbrir
    }

    private func importar(_ origem: URL) async -> LivroGuardado? {
        let item = Importacao(nomeDoArquivo: origem.lastPathComponent)
        importando.insert(item, at: 0)
        defer { importando.removeAll { $0 == item } }

        // Copia o arquivo para dentro do app antes de ler (arquivos de outros apps somem depois).
        let temporario = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let copia = temporario.appendingPathComponent(origem.lastPathComponent)
        let resultado: Result<(LivroLido, String), ErroDeLeitura> = await Task.detached(priority: .userInitiated) {
            let acesso = origem.startAccessingSecurityScopedResource()
            defer { if acesso { origem.stopAccessingSecurityScopedResource() } }
            do {
                try FileManager.default.createDirectory(at: temporario, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: origem, to: copia)
            } catch { return .failure(.corrompido) }
            guard let dados = try? Data(contentsOf: copia, options: .mappedIfSafe) else { return .failure(.corrompido) }
            let digital = SHA256.hash(data: dados).map { String(format: "%02x", $0) }.joined()
            do { return .success((try LeitorDeLivros.ler(copia), digital)) } catch let e as ErroDeLeitura {
                return .failure(e)
            } catch { return .failure(.corrompido) }
        }.value
        defer { try? FileManager.default.removeItem(at: temporario) }

        switch resultado {
        case .failure(let erro):
            aviso = .erro(erro)
            return nil
        case .success(let (lido, digital)):
            // Mesmo livro de novo: descarta a cópia, avisa e abre o que já existe (objeto Livro).
            if let existente = livros.first(where: { $0.impressaoDigital == digital }) {
                aviso = .repetido
                return existente
            }
            let id = UUID()
            let destino = pasta(de: id)
            do {
                try FileManager.default.createDirectory(at: destino, withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: copia, to: destino.appendingPathComponent("original." + origem.pathExtension.lowercased()))
                try JSONEncoder().encode(lido.texto).write(to: destino.appendingPathComponent("texto.json"))
                if let capa = lido.capa { try capa.write(to: destino.appendingPathComponent("capa")) }
            } catch {
                try? FileManager.default.removeItem(at: destino)
                aviso = .erro(.corrompido)
                return nil
            }
            let total = lido.texto.numeroDePalavras
            let livro = LivroGuardado(
                id: id, titulo: lido.titulo ?? origem.deletingPathExtension().lastPathComponent, autor: lido.autor,
                formato: lido.formato, nomeDoArquivo: origem.lastPathComponent,
                temCapa: lido.capa.flatMap(UIImage.init(data:)) != nil, impressaoDigital: digital,
                importadoEm: .now, abertoEm: nil, posicao: .inicio, totalDePalavras: total,
                palavrasRestantes: total, capituloAtual: 0, terminado: false)
            livros.append(livro)
            jaImportou = true
            ordenar()
            salvar()
            return livro
        }
    }

    // MARK: Ler o que está guardado

    func texto(de livro: LivroGuardado) -> TextoDoLivro? {
        guard let dados = try? Data(contentsOf: pasta(de: livro.id).appendingPathComponent("texto.json")),
              let texto = try? JSONDecoder().decode(TextoDoLivro.self, from: dados) else { return nil }
        if somas[livro.id] == nil {
            var acumulado = 0
            somas[livro.id] = texto.paragrafos.map { acumulado += TextoDoLivro.contarPalavras($0.texto); return acumulado }
        }
        return texto
    }

    func capa(de livro: LivroGuardado) -> UIImage? {
        guard livro.temCapa else { return nil }
        if let pronta = capas[livro.id] { return pronta }
        let imagem = (try? Data(contentsOf: pasta(de: livro.id).appendingPathComponent("capa"))).flatMap(UIImage.init(data:))
        capas[livro.id] = imagem
        return imagem
    }

    /// O livro pronto para o tocador: metadados, capa e texto.
    func lido(_ livro: LivroGuardado) -> LivroLido? {
        guard let texto = texto(de: livro) else { return nil }
        let capa = livro.temCapa ? try? Data(contentsOf: pasta(de: livro.id).appendingPathComponent("capa")) : nil
        return LivroLido(titulo: livro.titulo, autor: livro.autor, capa: capa, formato: livro.formato, texto: texto)
    }

    // MARK: Posição e abertura

    func registrarAbertura(_ id: UUID) {
        atualizar(id) { $0.abertoEm = .now }
        ordenar()
    }

    /// Guarda onde a narração parou. A tela de texto sempre abre nessa posição e o play continua dela.
    func salvarPosicao(_ id: UUID, _ posicao: Posicao, capitulo: Int) {
        atualizar(id) { livro in
            livro.posicao = posicao
            livro.capituloAtual = capitulo
            livro.terminado = false
            if let s = somas[id], posicao.paragrafo < s.count {
                let antes = posicao.paragrafo > 0 ? s[posicao.paragrafo - 1] : 0
                livro.palavrasRestantes = max(0, livro.totalDePalavras - antes)
            }
        }
    }

    /// Fluxo Ouvir um livro, Fim do livro: o livro passa a mostrar "Terminado".
    func marcarTerminado(_ id: UUID) {
        atualizar(id) { $0.terminado = true; $0.palavrasRestantes = 0 }
    }

    /// "Ouvir de novo" volta a posição para o começo.
    func recomecar(_ id: UUID) {
        atualizar(id) { $0.terminado = false; $0.posicao = .inicio; $0.capituloAtual = 0; $0.palavrasRestantes = $0.totalDePalavras }
    }

    // MARK: Excluir

    /// Apaga o arquivo original, a posição, as marcações e as narrações do livro (objeto Livro).
    func excluir(_ id: UUID) {
        livros.removeAll { $0.id == id }
        capas[id] = nil
        somas[id] = nil
        try? FileManager.default.removeItem(at: pasta(de: id))
        salvar()
    }

    // MARK: Interno

    private func atualizar(_ id: UUID, _ mudar: (inout LivroGuardado) -> Void) {
        guard let i = livros.firstIndex(where: { $0.id == id }) else { return }
        mudar(&livros[i])
        salvar()
    }

    private func ordenar() {
        livros.sort { $0.dataDeOrdem > $1.dataDeOrdem }
    }

    private func salvar() {
        try? JSONEncoder().encode(livros).write(to: indice, options: .atomic)
    }
}

// MARK: - Tempo restante

/// Atributo Tempo restante (objeto Livro): estimativa pelo número de palavras que faltam
/// e pela velocidade escolhida, porque a narração ainda não foi gerada.
enum TempoRestante {
    static func minutos(palavras: Int, velocidade: Float) -> Int {
        let porMinuto = CortadorDeTrechos.palavrasPorMinuto * Double(max(velocidade, 0.25))
        return Int((Double(palavras) / porMinuto).rounded(.up))
    }

    /// "4 h 12 min", "3 h 05 min" ou "37 min", como no canvas.
    static func texto(minutos: Int) -> String {
        let m = max(minutos, 1)
        if m < 60 { return "\(m) min" }
        return String(format: "%d h %02d min", m / 60, m % 60)
    }

    static func texto(palavras: Int, velocidade: Float) -> String {
        texto(minutos: minutos(palavras: palavras, velocidade: velocidade))
    }
}
