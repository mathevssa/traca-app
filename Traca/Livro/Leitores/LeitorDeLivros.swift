import Foundation

/// Os formatos aceitos na V1 (Constituição, princípio "Abre os formatos comuns de ebook").
nonisolated enum Formato: String, Codable, CaseIterable {
    case epub = "EPUB", pdf = "PDF", mobi = "MOBI", azw3 = "AZW3", fb2 = "FB2", txt = "TXT", rtf = "RTF"

    init?(extensao: String) {
        switch extensao.lowercased() {
        case "epub": self = .epub
        case "pdf": self = .pdf
        case "mobi", "prc", "azw": self = .mobi
        case "azw3", "kf8": self = .azw3
        case "fb2": self = .fb2
        case "txt", "text": self = .txt
        case "rtf": self = .rtf
        default: return nil
        }
    }
}

/// O que sai da leitura de um arquivo: os metadados e o texto no formato único.
nonisolated struct LivroLido {
    var titulo: String?
    var autor: String?
    var capa: Data?
    var formato: Formato
    var texto: TextoDoLivro
}

/// Os três motivos de erro de importação, com mensagens em fluxos/importar-e-excluir-livros.md.
nonisolated enum ErroDeLeitura: Error, Equatable {
    case drm
    case corrompido
    case formatoNaoAceito
}

/// A porta de entrada: recebe um arquivo e devolve o livro no formato único.
nonisolated enum LeitorDeLivros {
    static func ler(_ url: URL) throws -> LivroLido {
        guard let formato = Formato(extensao: url.pathExtension) else { throw ErroDeLeitura.formatoNaoAceito }
        let dados: Data
        do { dados = try Data(contentsOf: url, options: .mappedIfSafe) } catch { throw ErroDeLeitura.corrompido }
        var livro: LivroLido
        switch formato {
        case .epub: livro = try LeitorEPUB.ler(dados)
        case .mobi, .azw3: livro = try LeitorMOBI.ler(dados, formato: formato)
        case .fb2: livro = try LeitorFB2.ler(dados)
        case .txt: livro = try LeitorTXT.ler(dados)
        case .rtf: livro = try LeitorRTF.ler(dados)
        case .pdf: livro = try LeitorPDF.ler(dados)
        }
        guard !livro.texto.paragrafos.isEmpty else { throw ErroDeLeitura.corrompido }
        // Atributo Título (objetos/livro.md): sem título, usa o nome do arquivo sem a extensão.
        if (livro.titulo ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            livro.titulo = url.deletingPathExtension().lastPathComponent
        }
        return livro
    }
}

// MARK: - Árvore XML simples, para OPF, NCX, nav do EPUB e FB2

nonisolated final class NoXML {
    let nome: String
    let atributos: [String: String]
    var filhos: [NoXML] = []
    var texto = ""
    weak var pai: NoXML?

    init(nome: String, atributos: [String: String]) { self.nome = nome; self.atributos = atributos }

    /// Nome sem prefixo ("dc:title" vira "title").
    var nomeLocal: String { nome.split(separator: ":").last.map(String.init) ?? nome }

    func todos(_ nomeLocal: String) -> [NoXML] {
        var r: [NoXML] = []
        func visitar(_ n: NoXML) { for f in n.filhos { if f.nomeLocal == nomeLocal { r.append(f) }; visitar(f) } }
        visitar(self)
        return r
    }

    func primeiro(_ nomeLocal: String) -> NoXML? { todos(nomeLocal).first }

    /// Todo o texto dentro do nó, inclusive dos filhos.
    var textoCompleto: String { texto + filhos.map(\.textoCompleto).joined() }

    func atributo(_ local: String) -> String? {
        atributos.first { ($0.key.split(separator: ":").last.map(String.init) ?? $0.key) == local }?.value
    }

    static func ler(_ dados: Data) -> NoXML? {
        let p = XMLParser(data: dados)
        let d = Delegado()
        p.delegate = d
        p.shouldProcessNamespaces = false
        return p.parse() || d.raiz.filhos.isEmpty == false ? d.raiz : nil
    }

    private final class Delegado: NSObject, XMLParserDelegate {
        let raiz = NoXML(nome: "#raiz", atributos: [:])
        lazy var atual = raiz
        func parser(_ p: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
            let n = NoXML(nome: e, atributos: a); n.pai = atual; atual.filhos.append(n); atual = n
        }
        func parser(_ p: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) { atual = atual.pai ?? raiz }
        func parser(_ p: XMLParser, foundCharacters s: String) { atual.texto += s }
    }
}

nonisolated extension String {
    /// Resolve um caminho relativo dentro do EPUB ("../Text/cap1.xhtml").
    func resolvido(relativoA base: String) -> String {
        let semAncora = self.split(separator: "#", maxSplits: 1).first.map(String.init) ?? self
        let decodificado = semAncora.removingPercentEncoding ?? semAncora
        var partes = base.split(separator: "/").map(String.init)
        for p in decodificado.split(separator: "/").map(String.init) {
            if p == ".." { if !partes.isEmpty { partes.removeLast() } } else if p != "." { partes.append(p) }
        }
        return partes.joined(separator: "/")
    }
}
