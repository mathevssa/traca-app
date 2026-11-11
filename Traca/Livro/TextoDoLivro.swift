import Foundation
import NaturalLanguage

// O formato único de texto do Traça.
//
// Todo arquivo importado (EPUB, PDF, MOBI, AZW3, FB2, TXT ou RTF) vira um TextoDoLivro:
// uma lista de parágrafos, com marcas de onde começa cada capítulo.
// A tela de texto, o corte em trechos e a voz trabalham só com esse formato,
// e nunca com o arquivo original.

/// Um ponto exato do livro: o parágrafo e a letra dentro dele.
/// É o que guarda a posição atual, as marcações e o começo e o fim de cada trecho.
nonisolated struct Posicao: Codable, Hashable, Comparable {
    /// Índice do parágrafo na lista de parágrafos do livro.
    var paragrafo: Int
    /// Distância, em unidades UTF-16, desde o começo do parágrafo.
    /// É a mesma medida que o iOS usa para texto (NSString), o que facilita destacar a palavra.
    var deslocamento: Int

    static let inicio = Posicao(paragrafo: 0, deslocamento: 0)

    static func < (a: Posicao, b: Posicao) -> Bool {
        (a.paragrafo, a.deslocamento) < (b.paragrafo, b.deslocamento)
    }
}

nonisolated struct Paragrafo: Codable, Hashable {
    enum Tipo: String, Codable {
        /// Texto do livro, que a voz lê.
        case corpo
        /// Título de capítulo ou de seção. A voz também lê, e a tela mostra com outro estilo.
        case titulo
    }

    var texto: String
    var tipo: Tipo = .corpo
}

nonisolated struct Capitulo: Codable, Hashable {
    var titulo: String
    /// O parágrafo onde o capítulo começa. O capítulo vai até o começo do próximo.
    var primeiroParagrafo: Int
}

nonisolated struct TextoDoLivro: Codable, Hashable {
    var paragrafos: [Paragrafo]
    var capitulos: [Capitulo]

    init(paragrafos: [Paragrafo], capitulos: [Capitulo] = []) {
        // Parágrafo vazio não serve para nada: nem a voz nem a tela usam.
        var limpos: [Paragrafo] = []
        var mapa: [Int: Int] = [:]
        for (i, p) in paragrafos.enumerated() {
            mapa[i] = limpos.count
            let t = TextoDoLivro.normalizarEspacos(p.texto)
            if !t.isEmpty { limpos.append(Paragrafo(texto: t, tipo: p.tipo)) }
        }
        self.paragrafos = limpos
        // Capítulos apontam para o primeiro parágrafo que sobrou depois da limpeza.
        var caps: [Capitulo] = []
        for c in capitulos {
            guard let novo = mapa[c.primeiroParagrafo], novo < limpos.count else { continue }
            if let ultimo = caps.last, ultimo.primeiroParagrafo == novo { caps[caps.count - 1] = Capitulo(titulo: c.titulo, primeiroParagrafo: novo); continue }
            caps.append(Capitulo(titulo: c.titulo, primeiroParagrafo: novo))
        }
        // Número e nome do capítulo em parágrafos seguidos ("I" e "Do título") viram um capítulo só: "I · Do título".
        var juntos: [Capitulo] = []
        for c in caps {
            if let u = juntos.last, c.primeiroParagrafo - u.primeiroParagrafo == 1,
               limpos[u.primeiroParagrafo].texto.count <= 12 {
                let titulo = [u.titulo, c.titulo].filter { !$0.isEmpty }.joined(separator: " · ")
                juntos[juntos.count - 1] = Capitulo(titulo: titulo, primeiroParagrafo: u.primeiroParagrafo)
            } else {
                juntos.append(c)
            }
        }
        caps = juntos
        // Atributo Capítulos (objetos/livro.md): sem sumário, o livro é um capítulo só.
        if caps.isEmpty, !limpos.isEmpty {
            caps = [Capitulo(titulo: "", primeiroParagrafo: 0)]
        } else if let primeiro = caps.first, primeiro.primeiroParagrafo > 0 {
            // O que vem antes do primeiro capítulo (folha de rosto, dedicatória) vira um capítulo sem título.
            caps.insert(Capitulo(titulo: "", primeiroParagrafo: 0), at: 0)
        }
        self.capitulos = caps
    }

    /// Junta espaços repetidos e quebras de linha soltas num espaço só.
    static func normalizarEspacos(_ s: String) -> String {
        var saida = ""
        saida.reserveCapacity(s.count)
        var ultimoEspaco = true
        for c in s {
            if c.isWhitespace || c == "\u{00AD}" {
                if c == "\u{00AD}" { continue } // hífen invisível de quebra
                if !ultimoEspaco { saida.append(" "); ultimoEspaco = true }
            } else {
                saida.append(c); ultimoEspaco = false
            }
        }
        if saida.last == " " { saida.removeLast() }
        return saida
    }

    var numeroDePalavras: Int {
        paragrafos.reduce(0) { $0 + Self.contarPalavras($1.texto) }
    }

    static func contarPalavras(_ texto: String) -> Int {
        var n = 0
        var dentro = false
        for c in texto.unicodeScalars {
            let letra = CharacterSet.alphanumerics.contains(c)
            if letra && !dentro { n += 1 }
            dentro = letra
        }
        return n
    }

    /// O capítulo em que uma posição está.
    func capitulo(em posicao: Posicao) -> Int {
        var resposta = 0
        for (i, c) in capitulos.enumerated() where c.primeiroParagrafo <= posicao.paragrafo { resposta = i }
        return resposta
    }
}

// MARK: - Frases e palavras

nonisolated extension Paragrafo {
    /// As frases do parágrafo, como intervalos em UTF-16.
    /// Servem para tocar numa frase e a voz ir até ela, e para os 5 minutos grátis
    /// pararem no fim de uma frase.
    var frases: [NSRange] { Self.intervalos(de: texto, unidade: .sentence) }

    /// As palavras do parágrafo, como intervalos em UTF-16. Servem para o destaque palavra por palavra.
    var palavras: [NSRange] { Self.intervalos(de: texto, unidade: .word) }

    static func intervalos(de texto: String, unidade: NLTokenUnit) -> [NSRange] {
        let tk = NLTokenizer(unit: unidade)
        tk.setLanguage(.portuguese)
        tk.string = texto
        return tk.tokens(for: texto.startIndex..<texto.endIndex).map { NSRange($0, in: texto) }
    }
}

// MARK: - Capítulos reconhecidos no próprio texto

nonisolated enum ReconhecedorDeCapitulos {
    /// Quando o arquivo não tem sumário (comum em PDF e TXT), procura títulos como
    /// "Capítulo 1", "CAPÍTULO XII", "Parte II" ou "Cap. 3" no começo de parágrafos curtos.
    /// Regra do atributo Capítulos em objetos/livro.md.
    static func reconhecer(em paragrafos: [Paragrafo]) -> [Capitulo] {
        var caps: [Capitulo] = []
        for (i, p) in paragrafos.enumerated() where pareceTitulo(p.texto) {
            caps.append(Capitulo(titulo: p.texto, primeiroParagrafo: i))
        }
        // Um único achado provavelmente é falso positivo (uma frase solta que começa com "Parte").
        if caps.count >= 2 { return caps }
        return romanos(em: paragrafos)
    }

    /// Capítulos numerados só com algarismo romano numa linha ("I", "II", "III"...), comum em TXT.
    /// Só vale se a sequência começar em I e seguir em ordem, para não confundir com outra coisa.
    static func romanos(em paragrafos: [Paragrafo]) -> [Capitulo] {
        var caps: [Capitulo] = []
        var esperado = 1
        for (i, p) in paragrafos.enumerated() {
            let t = p.texto.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "."))
            guard t.count <= 8, let n = valorRomano(t), n == esperado else { continue }
            // O nome do capítulo, se vier logo depois e for curto ("Do título.").
            var titulo = t
            if i + 1 < paragrafos.count, paragrafos[i + 1].texto.count <= 60, valorRomano(paragrafos[i + 1].texto) == nil {
                titulo += " · " + paragrafos[i + 1].texto
            }
            caps.append(Capitulo(titulo: titulo, primeiroParagrafo: i))
            esperado += 1
        }
        return caps.count >= 3 ? caps : []
    }

    static func valorRomano(_ s: String) -> Int? {
        let v: [Character: Int] = ["I": 1, "V": 5, "X": 10, "L": 50, "C": 100, "D": 500, "M": 1000]
        guard !s.isEmpty, s.allSatisfy({ v[$0] != nil }) else { return nil }
        var total = 0, anterior = 0
        for c in s.reversed() {
            let x = v[c]!
            total += x < anterior ? -x : x
            anterior = max(anterior, x)
        }
        return total
    }

    static func pareceTitulo(_ texto: String) -> Bool {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count <= 80 else { return false }
        return t.range(of: padrao, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static let padrao =
        #"^(cap[íi]tulo|cap\.|parte|livro|chapter|part)\s+([0-9]+|[ivxlcdm]+|primeir[oa]|segund[oa]|terceir[oa]|um|dois|tr[êe]s)\b"#
}
