import Testing
import Foundation
@testable import Traca

struct VozDoIPhoneTests {
    let texto = TextoDoLivro(paragrafos: [
        Paragrafo(texto: "Uma noite destas, vindo da cidade para o Engenho Novo, encontrei no trem da Central um rapaz aqui do bairro."),
        Paragrafo(texto: "Cumprimentou-me, sentou-se ao pé de mim, falou da lua e dos ministros."),
    ])

    @Test func temVozEmPortugues() {
        #expect(!VozDoIPhone().vozes.isEmpty)
    }

    @Test func gravaOAudioComOTempoDeCadaPalavra() async throws {
        let voz = VozDoIPhone()
        let id = try #require(voz.vozes.first?.id)
        let trecho = Trecho(indice: 0, primeiroParagrafo: 0, ultimoParagrafo: 1, palavras: 34)
        let destino = FileManager.default.temporaryDirectory.appendingPathComponent("trecho-0.caf")
        let audio = try await voz.gerar(trecho, de: texto, voz: id, destino: destino)

        #expect(FileManager.default.fileExists(atPath: audio.arquivo.path))
        #expect(audio.duracao > 3)
        // Uma marca por palavra, mais ou menos, nos dois parágrafos.
        #expect(audio.marcas.count >= 25)
        #expect(Set(audio.marcas.map(\.paragrafo)) == [0, 1])
        // As marcas estão em ordem e dentro do áudio.
        #expect(zip(audio.marcas, audio.marcas.dropFirst()).allSatisfy { $0.inicio <= $1.inicio })
        #expect((audio.marcas.last?.inicio ?? .infinity) < audio.duracao)
        // A posição de cada marca aponta para a palavra certa no parágrafo.
        let lua = audio.marcas.first { m in
            m.paragrafo == 1 && (texto.paragrafos[1].texto as NSString).substring(with: NSRange(location: m.local, length: m.tamanho)) == "lua"
        }
        #expect(lua != nil)
    }
}
