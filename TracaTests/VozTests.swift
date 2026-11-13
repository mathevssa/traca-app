import Testing
import Foundation
@testable import Traca

@MainActor
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
        let trecho = Trecho(inicio: .inicio, ultimoParagrafo: 1, palavras: 34)
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

    /// No iPhone a voz mandava um "pedaço vazio" entre parágrafos, e o áudio era cortado ali.
    /// Este teste garante que todos os parágrafos do trecho entram no áudio.
    @Test func naoCortaOAudioEntreParagrafos() async throws {
        let paragrafos = (1...6).map { n in
            Paragrafo(texto: "Este é o parágrafo número \(n). —Medo! Ora, medo! A verdade é que eu só vim a aprender equitação mais tarde.")
        }
        let livro = TextoDoLivro(paragrafos: paragrafos)
        let voz = VozDoIPhone()
        let id = try #require(voz.vozes.first?.id)
        let trecho = Trecho(inicio: .inicio, ultimoParagrafo: 5, palavras: 120)
        let destino = FileManager.default.temporaryDirectory.appendingPathComponent("trecho-varios.caf")
        let audio = try await voz.gerar(trecho, de: livro, voz: id, destino: destino)
        #expect(Set(audio.marcas.map(\.paragrafo)) == Set(0...5))
        #expect((audio.marcas.last?.inicio ?? .infinity) < audio.duracao)
        #expect(audio.duracao > 25)
    }
}
