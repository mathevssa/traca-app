import Foundation

/// MOBI e AZW3 (Kindle sem DRM). Implementação própria, sem biblioteca de terceiros:
/// as bibliotecas conhecidas têm licença GPL ou LGPL, que não combinam com a App Store.
///
/// Os dois formatos usam o mesmo "envelope" (PalmDB). Dentro dele:
/// - MOBI clássico: HTML antigo, com âncoras "filepos" que apontam para posições do texto;
/// - AZW3 (KF8): HTML moderno, dividido em pedaços, seguido de CSS.
/// Arquivos "combo" trazem os dois; nesse caso lemos a parte MOBI clássica, que é mais simples.
enum LeitorMOBI {
    static func ler(_ dados: Data, formato: Formato) throws -> LivroLido {
        let b = [UInt8](dados)
        guard b.count > 78 else { throw ErroDeLeitura.corrompido }
        let tipo = String(decoding: b[60..<68], as: UTF8.self)
        guard tipo == "BOOKMOBI" || tipo == "TEXtREAd" else { throw ErroDeLeitura.corrompido }

        let numRegistros = be16(b, 76)
        var inicios: [Int] = []
        for i in 0..<numRegistros { inicios.append(be32(b, 78 + i * 8)) }
        inicios.append(b.count)
        func registro(_ i: Int) -> ArraySlice<UInt8> {
            guard i + 1 < inicios.count, inicios[i] <= inicios[i + 1], inicios[i + 1] <= b.count else { return [] }
            return b[inicios[i]..<inicios[i + 1]]
        }

        let r0 = Array(registro(0))
        guard r0.count >= 16 else { throw ErroDeLeitura.corrompido }
        let compressao = be16(r0, 0)
        let qtdTexto = be16(r0, 8)
        let criptografia = be16(r0, 12)
        if criptografia != 0 { throw ErroDeLeitura.drm }

        var codificacao = 1252
        var extraFlags = 0
        var titulo: String?
        var autor: String?
        var capa: Data?
        var primeiraImagem = -1
        if r0.count > 24, String(decoding: r0[16..<20], as: UTF8.self) == "MOBI" {
            let tamCabecalho = be32(r0, 20)
            codificacao = be32(r0, 28)
            if r0.count >= 0x70 { primeiraImagem = be32(r0, 0x6C) }
            if tamCabecalho >= 0xE4, r0.count >= 0xF4 { extraFlags = be16(r0, 0xF2) }
            let nomeOff = be32(r0, 0x54), nomeLen = be32(r0, 0x58)
            if nomeOff + nomeLen <= r0.count { titulo = decodificar(Array(r0[nomeOff..<(nomeOff + nomeLen)]), codificacao) }
            // EXTH: metadados extras (autor, título atualizado, capa)
            if be32(r0, 0x80) & 0x40 != 0 {
                var o = 16 + tamCabecalho
                if o + 12 <= r0.count, String(decoding: r0[o..<(o + 4)], as: UTF8.self) == "EXTH" {
                    let qtd = be32(r0, o + 8); o += 12
                    for _ in 0..<qtd {
                        guard o + 8 <= r0.count else { break }
                        let t = be32(r0, o), len = be32(r0, o + 4)
                        guard len >= 8, o + len <= r0.count else { break }
                        let valor = Array(r0[(o + 8)..<(o + len)])
                        switch t {
                        case 100:
                            let nome = decodificar(valor, codificacao) ?? ""
                            autor = autor.map { $0 + " & " + nome } ?? nome
                        case 503: titulo = decodificar(valor, codificacao) ?? titulo
                        case 201 where valor.count >= 4 && primeiraImagem > 0:
                            let idx = primeiraImagem + be32(valor, 0)
                            let img = registro(idx)
                            if !img.isEmpty { capa = Data(img) }
                        default: break
                        }
                        o += len
                    }
                }
            }
        }

        // Texto: junta os registros de texto, descompactados.
        var huff: HuffCdic?
        if compressao == 17480 { huff = try HuffCdic(r0: r0, registro: registro) }
        var texto: [UInt8] = []
        for i in 1...max(1, qtdTexto) where qtdTexto > 0 {
            var reg = Array(registro(i))
            reg = removerFinal(reg, flags: extraFlags)
            switch compressao {
            case 1: texto += reg
            case 2: texto += descompactarPalmDOC(reg)
            case 17480: texto += try huff!.descompactar(reg)
            default: throw ErroDeLeitura.corrompido
            }
        }

        var html = decodificar(texto, codificacao) ?? ""
        // KF8: depois do último </html> vêm as folhas de estilo, que não são texto do livro.
        if let ultimo = html.range(of: "</html>", options: [.backwards, .caseInsensitive]) {
            html = String(html[..<ultimo.upperBound])
        }

        // Âncoras "filepos" do MOBI clássico: posições em bytes, que viram capítulos.
        var conversor = HTMLParaTexto()
        let alvos = filepos(em: html)
        if alvos.isEmpty {
            conversor.adicionar(html)
        } else {
            // Corta o texto nos pontos de cada âncora e marca o parágrafo de cada uma.
            let utf8 = Array(html.utf8)
            var inicio = 0
            for alvo in alvos.map(\.alvo).sorted() where alvo > inicio && alvo < utf8.count {
                conversor.adicionar(String(decoding: utf8[inicio..<alvo], as: UTF8.self))
                conversor.registrarAncora("filepos:\(alvo)")
                inicio = alvo
            }
            conversor.adicionar(String(decoding: utf8[inicio...], as: UTF8.self))
        }

        var capitulos: [Capitulo] = []
        for a in alvos.sorted(by: { $0.alvo < $1.alvo }) {
            guard let p = conversor.ancoras["filepos:\(a.alvo)"] else { continue }
            if let u = capitulos.last, u.primeiroParagrafo >= p { continue }
            capitulos.append(Capitulo(titulo: a.rotulo, primeiroParagrafo: p))
        }
        if capitulos.count < 2 { capitulos = capitulosPelosTitulos(conversor.paragrafos) }
        if capitulos.isEmpty { capitulos = ReconhecedorDeCapitulos.reconhecer(em: conversor.paragrafos) }

        return LivroLido(titulo: titulo.map(TextoDoLivro.normalizarEspacos), autor: autor.map(TextoDoLivro.normalizarEspacos),
                         capa: capa, formato: formato,
                         texto: TextoDoLivro(paragrafos: conversor.paragrafos, capitulos: capitulos))
    }

    /// Sem sumário utilizável: cada título (h1, h2...) vira um capítulo.
    static func capitulosPelosTitulos(_ ps: [Paragrafo]) -> [Capitulo] {
        let caps = ps.enumerated().filter { $0.element.tipo == .titulo }.map { Capitulo(titulo: $0.element.texto, primeiroParagrafo: $0.offset) }
        return caps.count >= 2 ? caps : []
    }

    /// Links do sumário do MOBI clássico: <a filepos=00012345>Capítulo I</a>.
    static func filepos(em html: String) -> [(alvo: Int, rotulo: String)] {
        guard let re = try? NSRegularExpression(pattern: #"<a\s[^>]*filepos\s*=\s*"?0*([0-9]+)"?[^>]*>(.*?)</a>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        var vistos = Set<Int>()
        var r: [(Int, String)] = []
        for m in re.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let ra = Range(m.range(at: 1), in: html), let alvo = Int(html[ra]),
                  let rr = Range(m.range(at: 2), in: html) else { continue }
            var conv = HTMLParaTexto(); conv.adicionar(String(html[rr]))
            let rotulo = conv.paragrafos.map(\.texto).joined(separator: " ")
            // Link sem texto, ou só número, costuma ser nota de rodapé, não capítulo.
            guard !rotulo.isEmpty, rotulo.rangeOfCharacter(from: .letters) != nil, vistos.insert(alvo).inserted else { continue }
            r.append((alvo, rotulo))
        }
        return r
    }

    // MARK: Detalhes do formato

    static func be16(_ b: [UInt8], _ o: Int) -> Int { o + 2 <= b.count ? Int(b[o]) << 8 | Int(b[o + 1]) : 0 }
    static func be32(_ b: [UInt8], _ o: Int) -> Int { o + 4 <= b.count ? be16(b, o) << 16 | be16(b, o + 2) : 0 }

    static func decodificar(_ b: [UInt8], _ codificacao: Int) -> String? {
        if codificacao == 65001 { return String(decoding: b, as: UTF8.self) }
        return String(bytes: b, encoding: .windowsCP1252)
    }

    /// Cada registro de texto pode ter dados extras no final, que não são texto.
    static func removerFinal(_ reg: [UInt8], flags: Int) -> [UInt8] {
        func tamanho(_ d: ArraySlice<UInt8>) -> Int {
            var n = 0
            for v in d.suffix(4) {
                if v & 0x80 != 0 { n = 0 }
                n = (n << 7) | Int(v & 0x7F)
            }
            return n
        }
        var num = 0
        var f = flags >> 1
        while f != 0 {
            if f & 1 != 0, num < reg.count { num += tamanho(reg[0..<(reg.count - num)]) }
            f >>= 1
        }
        if flags & 1 != 0, reg.count - num - 1 >= 0 { num += Int(reg[reg.count - num - 1] & 3) + 1 }
        return Array(reg[0..<max(0, reg.count - num)])
    }

    /// Compressão PalmDOC (uma variação simples de LZ77).
    static func descompactarPalmDOC(_ e: [UInt8]) -> [UInt8] {
        var s: [UInt8] = []
        s.reserveCapacity(4096)
        var i = 0
        while i < e.count {
            let c = e[i]; i += 1
            switch c {
            case 0x01...0x08:
                let n = Int(c)
                s += e[i..<min(i + n, e.count)]; i += n
            case 0x80...0xBF:
                guard i < e.count else { break }
                let par = (Int(c) << 8 | Int(e[i])) & 0x3FFF; i += 1
                let distancia = par >> 3, tamanho = (par & 7) + 3
                guard distancia > 0, distancia <= s.count else { continue }
                for _ in 0..<tamanho { s.append(s[s.count - distancia]) }
            case 0xC0...0xFF:
                s.append(0x20); s.append(c ^ 0x80)
            default:
                s.append(c)
            }
        }
        return s
    }
}

/// Compressão HUFF/CDIC, usada por arquivos gerados pelo Kindlegen.
struct HuffCdic {
    private var dict1: [(codelen: Int, term: Bool, maxcode: UInt64)] = []
    private var mincode: [UInt64] = Array(repeating: 0, count: 33)
    private var maxcode: [UInt64] = Array(repeating: 0, count: 33)
    private var dicionario: [(dados: [UInt8], pronto: Bool)] = []

    init(r0: [UInt8], registro: (Int) -> ArraySlice<UInt8>) throws {
        let be32 = LeitorMOBI.be32
        let primeiro = be32(r0, 0x70), qtd = be32(r0, 0x74)
        guard qtd >= 2 else { throw ErroDeLeitura.corrompido }
        let huff = Array(registro(primeiro))
        guard huff.count >= 24, String(decoding: huff[0..<4], as: UTF8.self) == "HUFF" else { throw ErroDeLeitura.corrompido }
        let off1 = be32(huff, 8), off2 = be32(huff, 12)
        for i in 0..<256 {
            let v = be32(huff, off1 + i * 4)
            let codelen = v & 0x1F, term = v & 0x80 != 0
            let max = (UInt64(v >> 8) + 1) << (32 - codelen) &- 1
            dict1.append((codelen, term, max))
        }
        for i in 1...32 {
            mincode[i] = UInt64(be32(huff, off2 + (i - 1) * 8)) << (32 - i)
            maxcode[i] = ((UInt64(be32(huff, off2 + (i - 1) * 8 + 4)) + 1) << (32 - i)) &- 1
        }
        for r in (primeiro + 1)..<(primeiro + qtd) {
            let cdic = Array(registro(r))
            guard cdic.count >= 16, String(decoding: cdic[0..<4], as: UTF8.self) == "CDIC" else { throw ErroDeLeitura.corrompido }
            let total = be32(cdic, 8), bits = be32(cdic, 12)
            let n = min(1 << bits, total - dicionario.count)
            for j in 0..<n {
                let off = LeitorMOBI.be16(cdic, 16 + j * 2)
                let len = LeitorMOBI.be16(cdic, 16 + off)
                let ini = 18 + off, tam = len & 0x7FFF
                guard ini + tam <= cdic.count else { throw ErroDeLeitura.corrompido }
                dicionario.append((Array(cdic[ini..<(ini + tam)]), len & 0x8000 != 0))
            }
        }
    }

    mutating func descompactar(_ dados: [UInt8]) throws -> [UInt8] {
        var s: [UInt8] = []
        var bits = dados.count * 8
        let d = dados + [UInt8](repeating: 0, count: 8)
        var x: UInt64 = 0
        for i in 0..<8 { x = x << 8 | UInt64(d[i]) }
        var pos = 0, n = 32
        while true {
            if n <= 0 {
                pos += 4
                x = 0
                for i in 0..<8 { x = x << 8 | UInt64(pos + i < d.count ? d[pos + i] : 0) }
                n += 32
            }
            let code = (x >> UInt64(n)) & 0xFFFF_FFFF
            var (codelen, term, maxc) = dict1[Int(code >> 24)]
            if !term {
                while codelen < 32, code < mincode[codelen] { codelen += 1 }
                maxc = maxcode[codelen]
            }
            n -= codelen
            bits -= codelen
            if bits < 0 { break }
            let r = Int((maxc &- code) >> UInt64(32 - codelen))
            guard r < dicionario.count else { throw ErroDeLeitura.corrompido }
            var (slice, pronto) = dicionario[r]
            if !pronto {
                dicionario[r] = ([], true)
                slice = try descompactar(slice)
                dicionario[r] = (slice, true)
            }
            s += slice
        }
        return s
    }
}
