import Testing
import Foundation
@testable import Traca

@MainActor
struct TrechosTests {
    func livro(_ palavrasPorParagrafo: [Int], capitulos: [Int] = []) -> TextoDoLivro {
        TextoDoLivro(paragrafos: palavrasPorParagrafo.map { Paragrafo(texto: Array(repeating: "palavra", count: $0).joined(separator: " ")) },
                     capitulos: capitulos.map { Capitulo(titulo: "Cap \($0)", primeiroParagrafo: $0) })
    }

    @Test func trechoTemCercaDeCincoMinutosETerminaNoFimDoParagrafo() throws {
        let t = livro(Array(repeating: 100, count: 120))
        let tr = try #require(CortadorDeTrechos.trecho(aPartirDe: .inicio, em: t))
        #expect(tr.palavras >= CortadorDeTrechos.palavrasPorTrecho)
        #expect(tr.palavras < CortadorDeTrechos.palavrasPorTrecho + 100)
    }

    @Test func comecaOndeOLeitorTocou() throws {
        // Tocar lá na frente não gera o que ficou para trás.
        let t = livro(Array(repeating: 100, count: 120))
        let tr = try #require(CortadorDeTrechos.trecho(aPartirDe: Posicao(paragrafo: 57, deslocamento: 0), em: t))
        #expect(tr.primeiroParagrafo == 57)
    }

    @Test func comecaNoMeioDoParagrafo() throws {
        let t = TextoDoLivro(paragrafos: [Paragrafo(texto: "Uma frase. Outra frase aqui.")])
        let tr = try #require(CortadorDeTrechos.trecho(aPartirDe: Posicao(paragrafo: 0, deslocamento: 11), em: t))
        #expect(tr.palavras == 3)
        let (fala, _) = VozDoIPhone.montarTexto(tr, de: t)
        #expect(fala == "Outra frase aqui.")
    }

    @Test func paraNaViradaDeCapitulo() throws {
        let t = livro(Array(repeating: 100, count: 20), capitulos: [0, 3, 10])
        let tr = try #require(CortadorDeTrechos.trecho(aPartirDe: .inicio, em: t))
        #expect(tr.paragrafos == 0...2)
        let proximo = try #require(CortadorDeTrechos.proximo(depoisDe: tr, em: t))
        #expect(proximo.primeiroParagrafo == 3)
    }

    @Test func nuncaCortaNoMeioDoParagrafo() throws {
        let t = livro([3000, 800]) // um parágrafo de 20 minutos fica inteiro
        let tr = try #require(CortadorDeTrechos.trecho(aPartirDe: .inicio, em: t))
        #expect(tr.paragrafos == 0...0)
    }

    @Test func traduzAPosicaoDasPalavrasComDeslocamento() {
        let inicios = [(paragrafo: 4, inicio: 0, base: 11), (paragrafo: 5, inicio: 20, base: 0)]
        #expect(VozDoIPhone.localizar(6, em: inicios) == (4, 17))
        #expect(VozDoIPhone.localizar(25, em: inicios) == (5, 5))
    }
}

struct GutenbergTests {
    @Test func tiraALicencaDoComecoEDoFim() {
        let t = TextoDoLivro(paragrafos: [
            Paragrafo(texto: "The Project Gutenberg eBook of Dom Casmurro"),
            Paragrafo(texto: "This eBook is for the use of anyone anywhere."),
            Paragrafo(texto: "*** START OF THE PROJECT GUTENBERG EBOOK DOM CASMURRO ***"),
            Paragrafo(texto: "DOM CASMURRO"),
            Paragrafo(texto: "Uma noite destas."),
            Paragrafo(texto: "*** END OF THE PROJECT GUTENBERG EBOOK DOM CASMURRO ***"),
            Paragrafo(texto: "Updated editions will replace the previous one."),
        ], capitulos: [Capitulo(titulo: "I", primeiroParagrafo: 4)])
        let limpo = t.semLicencaDoGutenberg()
        #expect(limpo.paragrafos.map(\.texto) == ["DOM CASMURRO", "Uma noite destas."])
        #expect(limpo.capitulos.last?.primeiroParagrafo == 1)
    }

    @Test func livroSemLicencaFicaIgual() {
        let t = TextoDoLivro(paragrafos: [Paragrafo(texto: "Texto comum.")])
        #expect(t.semLicencaDoGutenberg() == t)
    }

    @Test func livroRealComecaNaObra() throws {
        try #require(LivrosDeTeste.existe("dom-casmurro.epub"), "Livro de teste ausente")
        let t = try LeitorDeLivros.ler(LivrosDeTeste.url("dom-casmurro.epub")).texto
        #expect(t.paragrafos.first?.texto == "DOM CASMURRO")
        #expect(!t.paragrafos.contains { $0.texto.contains("PROJECT GUTENBERG") })
    }
}
