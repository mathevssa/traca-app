import Foundation

/// Texto puro. Descobre a codificação, separa os parágrafos e tira o cabeçalho
/// e o rodapé do Project Gutenberg, que não fazem parte do livro.
nonisolated enum LeitorTXT {
    static func ler(_ dados: Data) throws -> LivroLido {
        guard var s = String(data: dados, encoding: .utf8) ?? String(data: dados, encoding: .windowsCP1252) else {
            throw ErroDeLeitura.corrompido
        }
        s = s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if s.hasPrefix("\u{FEFF}") { s.removeFirst() }

        var titulo: String?
        var autor: String?
        if let ini = s.range(of: #"\*\*\* ?START OF (THE|THIS) PROJECT GUTENBERG[^\n]*\n"#, options: .regularExpression) {
            let cabecalho = s[..<ini.lowerBound]
            titulo = valor("Title", em: cabecalho)
            autor = valor("Author", em: cabecalho)
            s = String(s[ini.upperBound...])
        }
        if let fim = s.range(of: #"\*\*\* ?END OF (THE|THIS) PROJECT GUTENBERG"#, options: .regularExpression) {
            s = String(s[..<fim.lowerBound])
        }

        let paragrafos = separar(s).map { Paragrafo(texto: TextoDoLivro.normalizarEspacos($0.texto)) }.filter { !$0.texto.isEmpty }
        let caps = ReconhecedorDeCapitulos.reconhecer(em: paragrafos)
        var ps = paragrafos
        for c in caps {
            ps[c.primeiroParagrafo].tipo = .titulo
            if c.titulo.contains(" · "), c.primeiroParagrafo + 1 < ps.count { ps[c.primeiroParagrafo + 1].tipo = .titulo }
        }
        return LivroLido(titulo: titulo, autor: autor, capa: nil, formato: .txt, texto: TextoDoLivro(paragrafos: ps, capitulos: caps))
    }

    /// Se o arquivo separa parágrafos com linha em branco, as linhas de dentro são só quebra de margem.
    /// Se não separa, cada linha é um parágrafo.
    static func separar(_ s: String) -> [Paragrafo] {
        let linhas = s.components(separatedBy: "\n")
        let brancas = linhas.filter { $0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        if brancas * 10 >= linhas.count {
            return dividir(s, por: #"\n[ \t]*\n"#).map { Paragrafo(texto: $0) }
        }
        return linhas.map { Paragrafo(texto: $0) }
    }

    private static func valor(_ campo: String, em texto: Substring) -> String? {
        for linha in texto.split(separator: "\n") where linha.hasPrefix(campo + ":") {
            return linha.dropFirst(campo.count + 1).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    static func dividir(_ s: String, por padrao: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: padrao) else { return [s] }
        var partes: [String] = []
        var inicio = s.startIndex
        for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
            guard let r = Range(m.range, in: s) else { continue }
            partes.append(String(s[inicio..<r.lowerBound]))
            inicio = r.upperBound
        }
        partes.append(String(s[inicio...]))
        return partes
    }
}
