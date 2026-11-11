import Testing
import Foundation
@testable import Traca

struct TextoDoLivroTests {
    @Test func limpaParagrafosVaziosEEspacos() {
        let t = TextoDoLivro(paragrafos: [
            Paragrafo(texto: "  Uma   noite\n destas, "),
            Paragrafo(texto: "   "),
            Paragrafo(texto: "vindo da cidade"),
        ])
        #expect(t.paragrafos.map(\.texto) == ["Uma noite destas,", "vindo da cidade"])
    }

    @Test func livroSemSumarioViraUmCapituloSo() {
        let t = TextoDoLivro(paragrafos: [Paragrafo(texto: "a"), Paragrafo(texto: "b")])
        #expect(t.capitulos.count == 1)
        #expect(t.capitulos[0].primeiroParagrafo == 0)
    }

    @Test func capituloAcompanhaALimpeza() {
        let t = TextoDoLivro(
            paragrafos: [Paragrafo(texto: "Prefácio"), Paragrafo(texto: " "), Paragrafo(texto: "Capítulo 1", tipo: .titulo), Paragrafo(texto: "Texto.")],
            capitulos: [Capitulo(titulo: "Capítulo 1", primeiroParagrafo: 2)])
        #expect(t.capitulos.map(\.primeiroParagrafo) == [0, 1])
        #expect(t.capitulo(em: Posicao(paragrafo: 2, deslocamento: 0)) == 1)
    }

    @Test func reconheceTitulosDeCapitulo() {
        #expect(ReconhecedorDeCapitulos.pareceTitulo("CAPÍTULO XII"))
        #expect(ReconhecedorDeCapitulos.pareceTitulo("Capitulo 3 — O agregado"))
        #expect(ReconhecedorDeCapitulos.pareceTitulo("Parte II"))
        #expect(!ReconhecedorDeCapitulos.pareceTitulo("Parte da noite passei acordado."))
    }

    @Test func frasesEPalavras() {
        let p = Paragrafo(texto: "Cumprimentou-me, sentou-se. Falou da lua e dos ministros.")
        #expect(p.frases.count == 2)
        let palavras = p.palavras.map { (p.texto as NSString).substring(with: $0) }
        #expect(palavras.contains("lua"))
    }

    @Test func contaPalavras() {
        #expect(TextoDoLivro.contarPalavras("Uma noite destas, vindo da cidade.") == 6)
    }

    @Test func posicaoOrdena() {
        #expect(Posicao(paragrafo: 1, deslocamento: 50) < Posicao(paragrafo: 2, deslocamento: 0))
    }
}
