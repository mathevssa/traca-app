import Foundation
import PDFKit

/// PDF, com o PDFKit do próprio iOS.
///
/// O PDF não sabe o que é parágrafo: ele só guarda linhas soltas numa página.
/// Este leitor remonta o texto pela posição de cada linha:
/// - tira cabeçalho e rodapé (número de página, título repetido no topo);
/// - percebe páginas em duas colunas e lê a coluna da esquerda antes da da direita;
/// - junta as linhas em parágrafos, pelo recuo, pelo espaço entre linhas e pela pontuação;
/// - junta a palavra cortada com hífen no fim da linha ("pala-" + "vra").
enum LeitorPDF {
    struct Linha {
        var texto: String
        var x: CGFloat, y: CGFloat, largura: CGFloat, altura: CGFloat
        var pagina: Int
    }

    static func ler(_ dados: Data) throws -> LivroLido {
        guard let doc = PDFDocument(data: dados) else { throw ErroDeLeitura.corrompido }
        if doc.isLocked { throw ErroDeLeitura.drm }

        var linhasPorPagina: [[Linha]] = []
        for i in 0..<doc.pageCount {
            guard let pagina = doc.page(at: i) else { linhasPorPagina.append([]); continue }
            linhasPorPagina.append(linhas(da: pagina, indice: i))
        }
        let repetidas = cabecalhosRepetidos(linhasPorPagina)

        var ps: [Paragrafo] = []
        var primeiroParagrafoDaPagina: [Int] = []
        var atual = ""
        var anterior: Linha?
        let todas = linhasPorPagina.flatMap { $0 }
        let margem = mediana(todas.map(\.x))
        let larguraTipica = percentil(todas.map(\.largura), 0.8)
        let espacoTipico = mediana(espacamentos(linhasPorPagina))

        for (indice, linhas) in linhasPorPagina.enumerated() {
            primeiroParagrafoDaPagina.append(ps.count + (atual.isEmpty ? 0 : 1))
            for l in linhas where !ehRuido(l, repetidas: repetidas, paginaAltura: alturaDaPagina(doc, indice)) {
                if let a = anterior, !atual.isEmpty {
                    let mesmaPagina = a.pagina == l.pagina
                    let recuo = l.x > margem + max(8, larguraTipica * 0.03)
                    let pulo = mesmaPagina && espacoTipico > 0 && (a.y - l.y) > espacoTipico * 1.6
                    let anteriorCurta = a.largura < larguraTipica * 0.75 && termina(a.texto)
                    // Fala de diálogo começa com travessão e sempre abre parágrafo novo.
                    let dialogo = (l.texto.hasPrefix("—") || l.texto.hasPrefix("– ")) && termina(a.texto)
                    if recuo || pulo || anteriorCurta || dialogo {
                        ps.append(Paragrafo(texto: atual)); atual = ""
                    }
                }
                atual = juntar(atual, l.texto)
                anterior = l
            }
        }
        if !atual.isEmpty { ps.append(Paragrafo(texto: atual)) }

        // Capítulos: o sumário do PDF (os "marcadores"), ou os títulos achados no texto.
        var caps: [Capitulo] = []
        if let raiz = doc.outlineRoot {
            var nivel = (0..<raiz.numberOfChildren).compactMap { raiz.child(at: $0) }
            if nivel.count == 1, let unico = nivel.first, unico.numberOfChildren > 1 {
                nivel = (0..<unico.numberOfChildren).compactMap { unico.child(at: $0) }
            }
            for item in nivel {
                guard let pag = item.destination?.page, case let i = doc.index(for: pag), i < primeiroParagrafoDaPagina.count else { continue }
                let p = min(primeiroParagrafoDaPagina[i], max(0, ps.count - 1))
                if let u = caps.last, u.primeiroParagrafo >= p { continue }
                caps.append(Capitulo(titulo: item.label ?? "", primeiroParagrafo: p))
            }
        }
        if caps.count < 2 {
            caps = ReconhecedorDeCapitulos.reconhecer(em: ps)
            for c in caps { ps[c.primeiroParagrafo].tipo = .titulo }
        }

        let attrs = doc.documentAttributes ?? [:]
        return LivroLido(titulo: attrs[PDFDocumentAttribute.titleAttribute] as? String,
                         autor: attrs[PDFDocumentAttribute.authorAttribute] as? String,
                         capa: nil, formato: .pdf, texto: TextoDoLivro(paragrafos: ps, capitulos: caps))
    }

    // MARK: Linhas de uma página

    static func linhas(da pagina: PDFPage, indice: Int) -> [Linha] {
        let caixa = pagina.bounds(for: .mediaBox)
        guard let sel = pagina.selection(for: caixa) else { return [] }
        var ls: [Linha] = []
        for s in sel.selectionsByLine() {
            guard let t = s.string?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { continue }
            let b = s.bounds(for: pagina)
            ls.append(Linha(texto: t, x: b.minX - caixa.minX, y: b.minY - caixa.minY, largura: b.width, altura: b.height, pagina: indice))
        }
        return ordenar(ls, larguraDaPagina: caixa.width)
    }

    /// Página em duas colunas: muitas linhas estreitas começando na metade direita.
    /// Aí lê toda a coluna da esquerda, de cima para baixo, e depois a da direita.
    static func ordenar(_ ls: [Linha], larguraDaPagina w: CGFloat) -> [Linha] {
        let direita = ls.filter { $0.x > w * 0.45 && $0.largura < w * 0.5 }
        let estreitas = ls.filter { $0.largura < w * 0.5 }
        let duasColunas = ls.count >= 10 && direita.count >= ls.count / 4 && estreitas.count >= ls.count * 2 / 3
        guard duasColunas else { return ls.sorted { $0.y > $1.y + 1 || (abs($0.y - $1.y) <= 1 && $0.x < $1.x) } }
        return ls.sorted { a, b in
            let ca = a.x > w * 0.45 ? 1 : 0, cb = b.x > w * 0.45 ? 1 : 0
            return ca != cb ? ca < cb : a.y > b.y
        }
    }

    // MARK: Cabeçalho, rodapé e número de página

    static func chave(_ t: String) -> String {
        t.lowercased().filter { $0.isLetter }
    }

    /// Textos que aparecem no topo ou no pé de muitas páginas (título do livro, nome do autor).
    static func cabecalhosRepetidos(_ paginas: [[Linha]]) -> Set<String> {
        var contagem: [String: Int] = [:]
        for ls in paginas {
            let extremos = (ls.prefix(2) + ls.suffix(2)).map { chave($0.texto) }.filter { !$0.isEmpty }
            for k in Set(extremos) { contagem[k, default: 0] += 1 }
        }
        let minimo = max(3, paginas.count / 5)
        return Set(contagem.filter { $0.value >= minimo }.keys)
    }

    static func ehRuido(_ l: Linha, repetidas: Set<String>, paginaAltura h: CGFloat) -> Bool {
        let perto = l.y < h * 0.08 || l.y > h * 0.90
        guard perto else { return false }
        let t = l.texto.trimmingCharacters(in: .whitespaces)
        if t.allSatisfy({ $0.isNumber || $0.isWhitespace || "-–—.|".contains($0) }) { return true }
        let k = chave(t)
        return !k.isEmpty && repetidas.contains(k)
    }

    static func alturaDaPagina(_ doc: PDFDocument, _ i: Int) -> CGFloat {
        doc.page(at: i)?.bounds(for: .mediaBox).height ?? 800
    }

    // MARK: Juntar linhas

    /// Pronomes que vêm depois de hífen ("sentou-se"): o hífen no fim da linha é de verdade.
    private static let cliticos: Set<String> = ["se", "me", "te", "lhe", "lhes", "o", "a", "os", "as", "lo", "la", "los", "las", "no", "na", "nos", "nas", "vos", "ia", "ei", "ás", "á", "ão", "emos", "eis"]

    static func juntar(_ atual: String, _ linha: String) -> String {
        guard !atual.isEmpty else { return linha }
        if atual.hasSuffix("-"), let primeira = linha.first, primeira.isLowercase {
            let antes = atual.dropLast()
            let proxima = String(linha.prefix { $0.isLetter }).lowercased()
            let anteriorTemHifen = antes.split(separator: " ").last?.contains("-") ?? false
            if cliticos.contains(proxima) || anteriorTemHifen { return atual + linha }
            return antes + linha
        }
        return atual + " " + linha
    }

    static func termina(_ t: String) -> Bool {
        guard let u = t.trimmingCharacters(in: .whitespaces).last else { return false }
        return ".!?:…»”\"".contains(u)
    }

    // MARK: Números auxiliares

    static func espacamentos(_ paginas: [[Linha]]) -> [CGFloat] {
        var r: [CGFloat] = []
        for ls in paginas where ls.count > 1 {
            for (a, b) in zip(ls, ls.dropFirst()) where a.y > b.y { r.append(a.y - b.y) }
        }
        return r
    }

    static func mediana(_ v: [CGFloat]) -> CGFloat { percentil(v, 0.5) }

    static func percentil(_ v: [CGFloat], _ p: Double) -> CGFloat {
        guard !v.isEmpty else { return 0 }
        let s = v.sorted()
        return s[min(s.count - 1, Int(Double(s.count - 1) * p))]
    }
}
