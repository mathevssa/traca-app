import Foundation

/// O momento do áudio em que uma palavra começa a ser dita.
/// É o que faz o texto acompanhar a voz (objetos/narracao.md, atributo Marcação de tempo).
struct MarcaDeTempo: Codable, Hashable {
    let paragrafo: Int
    /// Onde está a palavra dentro do parágrafo, em unidades UTF-16.
    let local: Int
    let tamanho: Int
    /// Segundos desde o começo do áudio do trecho.
    let inicio: TimeInterval
}

/// O resultado de gerar a voz de um trecho: o arquivo de áudio e o tempo de cada palavra.
struct AudioGerado: Codable, Hashable {
    let trecho: Int
    let voz: String
    let arquivo: URL
    let duracao: TimeInterval
    let marcas: [MarcaDeTempo]
}

/// Uma voz disponível para o leitor escolher.
struct OpcaoDeVoz: Hashable, Identifiable {
    let id: String
    let nome: String
}

/// A peça trocável da voz. Hoje é a voz do próprio iPhone; depois, a Inworld.
/// O resto do app só conversa com este contrato, então a troca não mexe em mais nada.
protocol ServicoDeVoz {
    var vozes: [OpcaoDeVoz] { get }

    /// Gera o áudio de um trecho e grava em `destino`.
    func gerar(_ trecho: Trecho, de texto: TextoDoLivro, voz: String, destino: URL) async throws -> AudioGerado
}

extension ServicoDeVoz {
    /// O texto que vai para a voz: os parágrafos do trecho, separados por linha em branco,
    /// e onde cada parágrafo começa nesse texto (para traduzir a posição das palavras de volta).
    static func montarTexto(_ trecho: Trecho, de texto: TextoDoLivro) -> (texto: String, inicios: [(paragrafo: Int, inicio: Int)]) {
        var s = ""
        var inicios: [(Int, Int)] = []
        for i in trecho.paragrafos {
            if !s.isEmpty { s += "\n\n" }
            inicios.append((i, (s as NSString).length))
            s += texto.paragrafos[i].texto
        }
        return (s, inicios)
    }

    /// Traduz uma posição no texto enviado à voz para (parágrafo, posição no parágrafo).
    static func localizar(_ posicao: Int, em inicios: [(paragrafo: Int, inicio: Int)]) -> (paragrafo: Int, local: Int) {
        var atual = inicios[0]
        for i in inicios where i.inicio <= posicao { atual = i }
        return (atual.paragrafo, posicao - atual.inicio)
    }
}
