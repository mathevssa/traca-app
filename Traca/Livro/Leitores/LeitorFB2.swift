import Foundation

/// FictionBook 2 (XML). Cada <section> com <title> é um capítulo.
enum LeitorFB2 {
    static func ler(_ dados: Data) throws -> LivroLido {
        guard let xml = NoXML.ler(dados), let fb = xml.primeiro("FictionBook") ?? xml.filhos.first else { throw ErroDeLeitura.corrompido }
        let info = fb.primeiro("title-info")
        let titulo = info?.primeiro("book-title")?.textoCompleto
        let autores = (info?.todos("author") ?? []).map { a in
            ["first-name", "middle-name", "last-name"].compactMap { a.primeiro($0)?.textoCompleto }.joined(separator: " ")
        }.filter { !$0.isEmpty }

        var capa: Data?
        if let href = info?.primeiro("coverpage")?.primeiro("image")?.atributo("href") {
            let id = href.hasPrefix("#") ? String(href.dropFirst()) : href
            if let bin = fb.todos("binary").first(where: { $0.atributo("id") == id }) {
                capa = Data(base64Encoded: bin.textoCompleto, options: .ignoreUnknownCharacters)
            }
        }

        var ps: [Paragrafo] = []
        var caps: [Capitulo] = []
        func visitar(_ no: NoXML) {
            for f in no.filhos {
                switch f.nomeLocal {
                case "section":
                    if let t = f.filhos.first(where: { $0.nomeLocal == "title" }) {
                        caps.append(Capitulo(titulo: TextoDoLivro.normalizarEspacos(t.todos("p").map(\.textoCompleto).joined(separator: " ")), primeiroParagrafo: ps.count))
                    }
                    visitar(f)
                case "title":
                    for p in f.todos("p") { ps.append(Paragrafo(texto: p.textoCompleto, tipo: .titulo)) }
                case "p", "v", "subtitle", "text-author":
                    ps.append(Paragrafo(texto: f.textoCompleto))
                case "binary", "description":
                    break
                default:
                    visitar(f) // epigraph, poem, stanza, cite...
                }
            }
        }
        // O corpo principal é o primeiro <body> que não é de notas.
        let corpos = fb.todos("body")
        if let corpo = corpos.first(where: { $0.atributo("name") != "notes" }) ?? corpos.first { visitar(corpo) }
        return LivroLido(titulo: titulo, autor: autores.isEmpty ? nil : autores.joined(separator: " & "),
                         capa: capa, formato: .fb2, texto: TextoDoLivro(paragrafos: ps, capitulos: caps))
    }
}
