import Foundation

/// EPUB 2 e 3. Lê a ordem de leitura (spine), o sumário (nav ou NCX), título, autor e capa.
nonisolated enum LeitorEPUB {
    static func ler(_ dados: Data) throws -> LivroLido {
        guard let zip = try? ArquivoZip(dados: dados) else { throw ErroDeLeitura.corrompido }
        if try temDRM(zip) { throw ErroDeLeitura.drm }

        guard let containerDados = try zip.ler("META-INF/container.xml"),
              let container = NoXML.ler(containerDados),
              let caminhoOPF = container.primeiro("rootfile")?.atributo("full-path"),
              let opfDados = try zip.ler(caminhoOPF),
              let opf = NoXML.ler(opfDados) else { throw ErroDeLeitura.corrompido }
        let pastaOPF = (caminhoOPF as NSString).deletingLastPathComponent

        // Manifesto: id -> (caminho, tipo, propriedades)
        var itens: [String: (href: String, tipo: String, props: String)] = [:]
        for item in opf.todos("item") {
            guard let id = item.atributo("id"), let href = item.atributo("href") else { continue }
            itens[id] = (href.resolvido(relativoA: pastaOPF), item.atributo("media-type") ?? "", item.atributo("properties") ?? "")
        }

        // Texto, na ordem do spine.
        var conversor = HTMLParaTexto()
        for ref in opf.todos("itemref") {
            guard let id = ref.atributo("idref"), let item = itens[id],
                  let html = try zip.ler(item.href) else { continue }
            conversor.adicionar(String(decoding: html, as: UTF8.self), prefixoDasAncoras: item.href)
        }

        // Sumário: EPUB 3 usa o documento "nav"; EPUB 2 usa o NCX.
        var entradasDoSumario: [(titulo: String, alvo: String)] = []
        if let nav = itens.values.first(where: { $0.props.contains("nav") }),
           let navDados = try zip.ler(nav.href), let navXML = NoXML.ler(navDados) {
            let pastaNav = (nav.href as NSString).deletingLastPathComponent
            let toc = navXML.todos("nav").first { ($0.atributo("type") ?? "").contains("toc") } ?? navXML
            for a in toc.todos("a") {
                guard let href = a.atributo("href") else { continue }
                entradasDoSumario.append((a.textoCompleto, alvo(href, pasta: pastaNav)))
            }
        }
        if entradasDoSumario.isEmpty,
           let ncx = itens.values.first(where: { $0.tipo == "application/x-dtbncx+xml" }),
           let ncxDados = try zip.ler(ncx.href), let ncxXML = NoXML.ler(ncxDados) {
            let pastaNCX = (ncx.href as NSString).deletingLastPathComponent
            for np in ncxXML.todos("navPoint") {
                guard let src = np.filhos.first(where: { $0.nomeLocal == "content" })?.atributo("src") else { continue }
                let rotulo = np.filhos.first { $0.nomeLocal == "navLabel" }?.textoCompleto ?? ""
                entradasDoSumario.append((rotulo, alvo(src, pasta: pastaNCX)))
            }
        }
        var capitulos: [Capitulo] = []
        for e in entradasDoSumario {
            guard let p = conversor.ancoras[e.alvo] ?? conversor.ancoras[e.alvo.components(separatedBy: "#")[0]] else { continue }
            if let ultimo = capitulos.last, ultimo.primeiroParagrafo >= p { continue } // fora de ordem ou repetido
            capitulos.append(Capitulo(titulo: TextoDoLivro.normalizarEspacos(e.titulo), primeiroParagrafo: p))
        }
        if capitulos.isEmpty { capitulos = ReconhecedorDeCapitulos.reconhecer(em: conversor.paragrafos) }

        // Metadados
        let titulo = opf.primeiro("title")?.textoCompleto
        let autor = opf.primeiro("creator")?.textoCompleto
        var capa: Data?
        let idCapa = opf.todos("meta").first { $0.atributo("name") == "cover" }?.atributo("content")
        if let item = itens.values.first(where: { $0.props.contains("cover-image") }) ?? idCapa.flatMap({ itens[$0] }),
           item.tipo.hasPrefix("image/") {
            capa = try? zip.ler(item.href)
        }

        return LivroLido(titulo: titulo.map(TextoDoLivro.normalizarEspacos),
                         autor: autor.map(TextoDoLivro.normalizarEspacos),
                         capa: capa, formato: .epub,
                         texto: TextoDoLivro(paragrafos: conversor.paragrafos, capitulos: capitulos))
    }

    private static func alvo(_ href: String, pasta: String) -> String {
        let partes = href.split(separator: "#", maxSplits: 1).map(String.init)
        let arquivo = partes[0].resolvido(relativoA: pasta)
        return partes.count > 1 ? arquivo + partes[1] : arquivo
    }

    /// Livro com DRM: tem o rights.xml da Adobe, ou um encryption.xml que cifra mais do que fontes.
    /// Cifrar só fontes ("ofuscação de fontes") é comum em EPUB sem DRM e não impede a leitura.
    static func temDRM(_ zip: ArquivoZip) throws -> Bool {
        if zip.entradas.keys.contains(where: { $0.lowercased() == "meta-inf/rights.xml" }) { return true }
        guard let enc = try zip.ler("META-INF/encryption.xml"), let xml = NoXML.ler(enc) else { return false }
        let fontes = ["http://www.idpf.org/2008/embedding", "http://ns.adobe.com/pdf/enc#RC"]
        for metodo in xml.todos("EncryptionMethod") {
            if let alg = metodo.atributo("Algorithm"), !fontes.contains(alg) { return true }
        }
        return false
    }
}
