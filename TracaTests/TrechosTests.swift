import Testing
import Foundation
@testable import Traca

struct TrechosTests {
    func livro(_ palavrasPorParagrafo: [Int]) -> TextoDoLivro {
        TextoDoLivro(paragrafos: palavrasPorParagrafo.map { Paragrafo(texto: Array(repeating: "palavra", count: $0).joined(separator: " ")) })
    }

    @Test func cobreOLivroInteiroSemBuracos() {
        let t = livro(Array(repeating: 100, count: 120)) // 12 mil palavras
        let trechos = CortadorDeTrechos.cortar(t)
        #expect(trechos.first?.primeiroParagrafo == 0)
        #expect(trechos.last?.ultimoParagrafo == t.paragrafos.count - 1)
        for (a, b) in zip(trechos, trechos.dropFirst()) { #expect(b.primeiroParagrafo == a.ultimoParagrafo + 1) }
        #expect(trechos.map(\.indice) == Array(0..<trechos.count))
    }

    @Test func cadaTrechoTemCercaDeCincoMinutos() {
        let t = livro(Array(repeating: 100, count: 120))
        let alvo = CortadorDeTrechos.palavrasPorTrecho
        for tr in CortadorDeTrechos.cortar(t).dropLast() {
            #expect(tr.palavras >= alvo && tr.palavras < alvo + 100)
        }
    }

    @Test func sobraCurtaEntraNoTrechoAnterior() {
        let alvo = CortadorDeTrechos.palavrasPorTrecho
        let t = livro([alvo, 10])
        let trechos = CortadorDeTrechos.cortar(t)
        #expect(trechos.count == 1)
        #expect(trechos[0].ultimoParagrafo == 1)
    }

    @Test func nuncaCortaNoMeioDoParagrafo() {
        let t = livro([3000, 800]) // um parágrafo de 20 minutos fica inteiro num trecho só
        let trechos = CortadorDeTrechos.cortar(t)
        #expect(trechos.map(\.paragrafos) == [0...0, 1...1])
    }

    @Test func achaOTrechoDeUmParagrafo() {
        let t = livro(Array(repeating: 100, count: 120))
        let trechos = CortadorDeTrechos.cortar(t)
        for p in [0, 7, 8, 59, 119] {
            let tr = CortadorDeTrechos.trecho(doParagrafo: p, em: trechos)
            #expect(tr?.paragrafos.contains(p) == true)
        }
    }

    @Test func livroRealViraTrechosDeCincoMinutos() throws {
        try #require(LivrosDeTeste.existe("dom-casmurro.epub"), "Livro de teste ausente")
        let t = try LeitorDeLivros.ler(LivrosDeTeste.url("dom-casmurro.epub")).texto
        let trechos = CortadorDeTrechos.cortar(t)
        let minutos = Double(t.numeroDePalavras) / CortadorDeTrechos.palavrasPorMinuto
        // Cerca de um trecho a cada 5 minutos de livro. Como o corte espera o fim do parágrafo,
        // os trechos passam um pouco dos 5 minutos e saem um pouco menos trechos.
        #expect(Double(trechos.count) > minutos / 5 * 0.85)
        #expect(Double(trechos.count) <= minutos / 5 + 1)
    }
}
