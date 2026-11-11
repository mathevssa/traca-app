import Foundation
import Compression

/// Leitor mínimo de arquivos ZIP (o EPUB é um ZIP por dentro).
/// Usa só o que já vem no iOS, sem biblioteca de terceiros.
nonisolated struct ArquivoZip {
    struct Entrada {
        let nome: String
        let metodo: UInt16
        let tamanhoCompactado: Int
        let tamanho: Int
        let deslocamentoDoCabecalho: Int
    }

    enum Erro: Error { case naoEZip, metodoNaoSuportado, corrompido }

    let dados: Data
    let entradas: [String: Entrada]

    init(dados: Data) throws {
        self.dados = dados
        let b = [UInt8](dados)
        func u16(_ o: Int) -> Int { Int(b[o]) | Int(b[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
        // Procura o "fim do diretório central" a partir do final do arquivo.
        guard b.count >= 22 else { throw Erro.naoEZip }
        var fim = -1
        var i = b.count - 22
        let limite = max(0, b.count - 22 - 65_535)
        while i >= limite {
            if b[i] == 0x50, b[i + 1] == 0x4B, b[i + 2] == 0x05, b[i + 3] == 0x06 { fim = i; break }
            i -= 1
        }
        guard fim >= 0 else { throw Erro.naoEZip }
        let total = u16(fim + 10)
        var o = u32(fim + 16)
        var mapa: [String: Entrada] = [:]
        for _ in 0..<total {
            guard o + 46 <= b.count, u32(o) == 0x0201_4B50 else { throw Erro.corrompido }
            let metodo = UInt16(u16(o + 10))
            let compactado = u32(o + 20), tamanho = u32(o + 24)
            let nLen = u16(o + 28), eLen = u16(o + 30), cLen = u16(o + 32)
            let local = u32(o + 42)
            guard o + 46 + nLen <= b.count else { throw Erro.corrompido }
            let nome = String(decoding: b[(o + 46)..<(o + 46 + nLen)], as: UTF8.self)
            mapa[nome] = Entrada(nome: nome, metodo: metodo, tamanhoCompactado: compactado, tamanho: tamanho, deslocamentoDoCabecalho: local)
            o += 46 + nLen + eLen + cLen
        }
        entradas = mapa
    }

    func ler(_ nome: String) throws -> Data? {
        guard let e = entradas[nome] ?? entradas.first(where: { $0.key.lowercased() == nome.lowercased() })?.value else { return nil }
        let o = e.deslocamentoDoCabecalho
        guard o + 30 <= dados.count else { throw Erro.corrompido }
        let nLen = Int(dados[dados.startIndex + o + 26]) | Int(dados[dados.startIndex + o + 27]) << 8
        let eLen = Int(dados[dados.startIndex + o + 28]) | Int(dados[dados.startIndex + o + 29]) << 8
        let inicio = o + 30 + nLen + eLen
        guard inicio + e.tamanhoCompactado <= dados.count else { throw Erro.corrompido }
        let bruto = dados.subdata(in: (dados.startIndex + inicio)..<(dados.startIndex + inicio + e.tamanhoCompactado))
        switch e.metodo {
        case 0: return bruto
        case 8: return try Self.descompactar(bruto, tamanho: e.tamanho)
        default: throw Erro.metodoNaoSuportado
        }
    }

    /// DEFLATE puro, que é o que o ZIP usa. No framework Compression ele se chama COMPRESSION_ZLIB.
    static func descompactar(_ entrada: Data, tamanho: Int) throws -> Data {
        guard tamanho > 0 else { return Data() }
        var saida = Data(count: tamanho)
        let escritos = saida.withUnsafeMutableBytes { dst in
            entrada.withUnsafeBytes { src in
                compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, tamanho,
                                          src.bindMemory(to: UInt8.self).baseAddress!, entrada.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        guard escritos == tamanho else { throw Erro.corrompido }
        return saida
    }
}
