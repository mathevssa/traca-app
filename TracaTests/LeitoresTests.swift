import Testing
import Foundation
@testable import Traca

/// Os livros de teste ficam fora do Git, na pasta "traca-livros-teste" da pasta pessoal do Mac
/// (fora de Documentos, que o macOS bloqueia para o simulador).
/// Sem a pasta, estes testes são pulados.
enum LivrosDeTeste {
    static let pasta: URL = {
        // A pasta pessoal é a parte do caminho deste arquivo até "/Users/<nome>".
        let partes = URL(fileURLWithPath: #filePath).pathComponents
        let casa = partes.count > 2 && partes[1] == "Users" ? "/Users/" + partes[2] : NSHomeDirectory()
        return URL(fileURLWithPath: casa).appendingPathComponent("traca-livros-teste")
    }()
    static func url(_ nome: String) -> URL { pasta.appendingPathComponent(nome) }
    static func existe(_ nome: String) -> Bool { FileManager.default.fileExists(atPath: url(nome).path) }
}

struct LeitoresComLivrosReais {
    @Test(arguments: [
        ("dom-casmurro.epub", Formato.epub), ("dom-casmurro.mobi", .mobi), ("dom-casmurro.azw3", .azw3),
        ("dom-casmurro.txt", .txt), ("dom-casmurro-convertido.fb2", .fb2),
        ("memorias-postumas.pdf", .pdf), ("quincas-borba-fuvest.pdf", .pdf), ("papeis-avulsos.rtf", .rtf),
    ])
    func leOLivroInteiro(_ nome: String, _ formato: Formato) throws {
        try #require(LivrosDeTeste.existe(nome), "Livro de teste ausente")
        let livro = try LeitorDeLivros.ler(LivrosDeTeste.url(nome))
        #expect(livro.formato == formato)
        #expect(livro.texto.paragrafos.count > 1000)
        #expect(livro.texto.numeroDePalavras > 50_000)
        #expect(!(livro.titulo ?? "").isEmpty)
    }

    @Test(arguments: ["dom-casmurro.epub", "dom-casmurro.mobi", "dom-casmurro.txt", "memorias-postumas.pdf", "quincas-borba-fuvest.pdf"])
    func achaOsCapitulos(_ nome: String) throws {
        try #require(LivrosDeTeste.existe(nome), "Livro de teste ausente")
        let livro = try LeitorDeLivros.ler(LivrosDeTeste.url(nome))
        #expect(livro.texto.capitulos.count > 100)
    }

    @Test func pdfSeparaAsFalasDoDialogo() throws {
        try #require(LivrosDeTeste.existe("quincas-borba-fuvest.pdf"), "Livro de teste ausente")
        let livro = try LeitorDeLivros.ler(LivrosDeTeste.url("quincas-borba-fuvest.pdf"))
        #expect(livro.texto.paragrafos.contains { $0.texto == "— Me parece que si." })
    }
}

struct LeitoresComErros {
    @Test func formatoNaoAceito() {
        #expect(throws: ErroDeLeitura.formatoNaoAceito) { try LeitorDeLivros.ler(URL(fileURLWithPath: "/tmp/livro.docx")) }
    }

    @Test func arquivoDanificado() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("danificado.epub")
        try Data((0..<2000).map { UInt8($0 % 251) }).write(to: url)
        #expect(throws: ErroDeLeitura.corrompido) { try LeitorDeLivros.ler(url) }
    }

    @Test func mobiComDRM() throws {
        // Envelope PalmDB mínimo com o campo de criptografia ligado.
        var b = [UInt8](repeating: 0, count: 78 + 8 * 2 + 2)
        b.replaceSubrange(60..<68, with: Array("BOOKMOBI".utf8))
        b[77] = 1 // um registro
        let inicioR0 = b.count
        b[78 + 3] = UInt8(inicioR0)
        var r0 = [UInt8](repeating: 0, count: 16)
        r0[1] = 2  // compressão PalmDOC
        r0[13] = 2 // criptografia Mobipocket
        b += r0
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("protegido.mobi")
        try Data(b).write(to: url)
        #expect(throws: ErroDeLeitura.drm) { try LeitorDeLivros.ler(url) }
    }

    @Test func palmDOCDescompacta() {
        // "aaa" literal + par distância/tamanho que repete "aaa" + espaço+letra
        let entrada: [UInt8] = [0x61, 0x61, 0x61, 0x80, 0x18, 0xE2]
        #expect(String(decoding: LeitorMOBI.descompactarPalmDOC(entrada), as: UTF8.self) == "aaaaaa b")
    }
}
