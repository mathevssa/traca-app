import Foundation

/// Transforma HTML (de EPUB, MOBI e AZW3) em parágrafos.
/// É tolerante: não exige HTML bem formado, porque arquivos MOBI costumam ter tags quebradas.
nonisolated struct HTMLParaTexto {
    /// Parágrafos encontrados, em ordem.
    private(set) var paragrafos: [Paragrafo] = []
    /// Para cada âncora (atributo id, name ou filepos), o parágrafo em que ela aparece.
    /// É assim que o sumário do arquivo vira capítulos.
    private(set) var ancoras: [String: Int] = [:]

    private var atual = ""
    private var tipoAtual: Paragrafo.Tipo = .corpo
    private var ignorando = 0 // dentro de <script>, <style>, <head>...

    private static let blocos: Set<String> = ["p", "div", "br", "li", "blockquote", "section", "article", "tr", "dd", "dt", "pre", "hr", "table", "ul", "ol", "body", "mbp:pagebreak", "figure", "figcaption", "aside", "header", "footer", "h1", "h2", "h3", "h4", "h5", "h6", "title"]
    private static let titulos: Set<String> = ["h1", "h2", "h3", "h4", "h5", "h6"]
    private static let ignorados: Set<String> = ["script", "style", "head", "svg", "math", "noscript"]

    /// Adiciona um documento HTML. `prefixoDasAncoras` diferencia arquivos de um EPUB (ex.: "cap1.xhtml#").
    mutating func adicionar(_ html: String, prefixoDasAncoras: String = "") {
        // Âncora do próprio arquivo, para sumário que aponta para "cap1.xhtml" sem "#".
        if !prefixoDasAncoras.isEmpty { ancoras[prefixoDasAncoras] = paragrafos.count }
        var i = html.startIndex
        while i < html.endIndex {
            let c = html[i]
            if c == "<" {
                guard let fim = html[i...].firstIndex(of: ">") else { break }
                let tag = html[html.index(after: i)..<fim]
                if tag.hasPrefix("!--") {
                    // Comentário: pula até o "-->".
                    if let fc = html.range(of: "-->", range: i..<html.endIndex) { i = fc.upperBound; continue }
                }
                tratarTag(String(tag), prefixo: prefixoDasAncoras)
                i = html.index(after: fim)
            } else if c == "&" {
                let (texto, prox) = Self.entidade(em: html, a: i)
                if ignorando == 0 { atual += texto }
                i = prox
            } else {
                if ignorando == 0 { atual.append(c) }
                i = html.index(after: i)
            }
        }
        fecharParagrafo()
    }

    private mutating func tratarTag(_ bruta: String, prefixo: String) {
        var t = bruta.trimmingCharacters(in: .whitespacesAndNewlines)
        let fechando = t.hasPrefix("/")
        if fechando { t.removeFirst() }
        let autoFechada = t.hasSuffix("/")
        let nome = String(t.prefix { !$0.isWhitespace && $0 != "/" }).lowercased()
        let nomeSemPrefixo = nome.split(separator: ":").last.map(String.init) ?? nome

        if Self.ignorados.contains(nomeSemPrefixo) {
            if fechando { ignorando = max(0, ignorando - 1) } else if !autoFechada { ignorando += 1 }
            return
        }
        if Self.blocos.contains(nome) || Self.blocos.contains(nomeSemPrefixo) {
            fecharParagrafo()
            if Self.titulos.contains(nomeSemPrefixo) { tipoAtual = fechando ? .corpo : .titulo }
        }
        if !fechando {
            for nomeAttr in ["id", "name", "filepos"] {
                if let v = Self.atributo(nomeAttr, em: t) { ancoras[prefixo + v] = paragrafos.count }
            }
        }
    }

    private mutating func fecharParagrafo() {
        let t = TextoDoLivro.normalizarEspacos(atual)
        if !t.isEmpty { paragrafos.append(Paragrafo(texto: t, tipo: tipoAtual)) }
        atual = ""
    }

    /// Posição das âncoras "filepos" do MOBI, que apontam para bytes do texto e não para ids.
    mutating func registrarAncora(_ nome: String) { ancoras[nome] = paragrafos.count }
    mutating func adicionarTextoBruto(_ s: String) { atual += s }
    mutating func quebrar() { fecharParagrafo() }

    static func atributo(_ nome: String, em tag: String) -> String? {
        let padrao = "(?:^|\\s)" + nome + "\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
        guard let re = try? NSRegularExpression(pattern: padrao, options: .caseInsensitive),
              let m = re.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) else { return nil }
        for g in 1...3 {
            if let r = Range(m.range(at: g), in: tag) { return String(tag[r]) }
        }
        return nil
    }

    private static let nomeadas: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "mdash": "—", "ndash": "–", "hellip": "…", "laquo": "«", "raquo": "»",
        "ldquo": "“", "rdquo": "”", "lsquo": "‘", "rsquo": "’", "shy": "",
        "aacute": "á", "eacute": "é", "iacute": "í", "oacute": "ó", "uacute": "ú",
        "Aacute": "Á", "Eacute": "É", "Iacute": "Í", "Oacute": "Ó", "Uacute": "Ú",
        "agrave": "à", "Agrave": "À", "acirc": "â", "ecirc": "ê", "ocirc": "ô",
        "Acirc": "Â", "Ecirc": "Ê", "Ocirc": "Ô", "atilde": "ã", "otilde": "õ",
        "Atilde": "Ã", "Otilde": "Õ", "ccedil": "ç", "Ccedil": "Ç", "uuml": "ü", "Uuml": "Ü",
    ]

    static func entidade(em s: String, a i: String.Index) -> (String, String.Index) {
        guard let pv = s[i...].prefix(12).firstIndex(of: ";") else { return ("&", s.index(after: i)) }
        let corpo = s[s.index(after: i)..<pv]
        let prox = s.index(after: pv)
        if corpo.hasPrefix("#") {
            let num = corpo.dropFirst()
            let valor = num.lowercased().hasPrefix("x") ? UInt32(num.dropFirst(), radix: 16) : UInt32(num)
            if let v = valor, let u = Unicode.Scalar(v) { return (String(Character(u)), prox) }
        } else if let t = nomeadas[String(corpo)] {
            return (t, prox)
        }
        return ("&", s.index(after: i))
    }
}
