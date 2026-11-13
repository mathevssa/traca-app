import Testing
import Foundation
@testable import Traca

@MainActor
struct BibliotecaTests {
    let pasta = FileManager.default.temporaryDirectory.appendingPathComponent("biblioteca-\(UUID().uuidString)")

    @Test func importaGuardaEReabre() async throws {
        try #require(LivrosDeTeste.existe("dom-casmurro.epub"), "Livro de teste ausente")
        let b = Biblioteca(pasta: pasta)
        let livro = try #require(await b.importar([LivrosDeTeste.url("dom-casmurro.epub")]))
        #expect(livro.titulo == "Dom Casmurro")
        #expect(livro.autor == "Machado de Assis")
        #expect(livro.temCapa)
        #expect(livro.abertoEm == nil)
        #expect(livro.palavrasRestantes == livro.totalDePalavras)
        // Uma biblioteca nova, na mesma pasta, encontra o livro guardado.
        let outra = Biblioteca(pasta: pasta)
        #expect(outra.livros.map(\.id) == [livro.id])
        #expect(outra.texto(de: livro)?.paragrafos.count ?? 0 > 1000)
    }

    @Test func reconheceOLivroRepetido() async throws {
        try #require(LivrosDeTeste.existe("dom-casmurro.epub"), "Livro de teste ausente")
        let b = Biblioteca(pasta: pasta)
        let primeiro = try #require(await b.importar([LivrosDeTeste.url("dom-casmurro.epub")]))
        let segundo = await b.importar([LivrosDeTeste.url("dom-casmurro.epub")])
        #expect(b.livros.count == 1)
        #expect(segundo?.id == primeiro.id)
        #expect(b.aviso == .repetido)
    }

    @Test func avisaQuandoOFormatoNaoEAceito() async throws {
        let arquivo = FileManager.default.temporaryDirectory.appendingPathComponent("planilha.xlsx")
        try Data("x".utf8).write(to: arquivo)
        let b = Biblioteca(pasta: pasta)
        #expect(await b.importar([arquivo]) == nil)
        #expect(b.aviso == .erro(.formatoNaoAceito))
        #expect(b.livros.isEmpty)
    }

    @Test func guardaAPosicaoEOTempoQueFalta() async throws {
        try #require(LivrosDeTeste.existe("dom-casmurro.txt"), "Livro de teste ausente")
        let b = Biblioteca(pasta: pasta)
        let livro = try #require(await b.importar([LivrosDeTeste.url("dom-casmurro.txt")]))
        _ = b.texto(de: livro)
        b.registrarAbertura(livro.id)
        b.salvarPosicao(livro.id, Posicao(paragrafo: 800, deslocamento: 12), capitulo: 40)
        let salvo = try #require(Biblioteca(pasta: pasta).livros.first)
        #expect(salvo.posicao == Posicao(paragrafo: 800, deslocamento: 12))
        #expect(salvo.abertoEm != nil)
        #expect(salvo.palavrasRestantes < salvo.totalDePalavras)
        #expect(salvo.palavrasRestantes > 0)
    }

    @Test func excluiTudoDoLivro() async throws {
        try #require(LivrosDeTeste.existe("dom-casmurro.epub"), "Livro de teste ausente")
        let b = Biblioteca(pasta: pasta)
        let livro = try #require(await b.importar([LivrosDeTeste.url("dom-casmurro.epub")]))
        b.excluir(livro.id)
        #expect(b.livros.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: pasta.appendingPathComponent(livro.id.uuidString).path))
        #expect(Biblioteca(pasta: pasta).livros.isEmpty)
    }

    @Test func formataOTempoComoNoCanvas() {
        #expect(TempoRestante.texto(minutos: 252) == "4 h 12 min")
        #expect(TempoRestante.texto(minutos: 185) == "3 h 05 min")
        #expect(TempoRestante.texto(minutos: 37) == "37 min")
    }
}
