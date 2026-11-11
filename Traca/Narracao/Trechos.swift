import Foundation

/// Um pedaço do livro de cerca de 5 minutos de voz, sempre terminando no fim de um parágrafo.
/// É a unidade que vai para o serviço de voz (objetos/narracao.md, atributo Trecho).
struct Trecho: Codable, Hashable, Identifiable {
    /// Posição do trecho no livro: 0 é o primeiro (os 5 minutos grátis).
    let indice: Int
    let primeiroParagrafo: Int
    /// Último parágrafo do trecho, incluído.
    let ultimoParagrafo: Int
    let palavras: Int

    var id: Int { indice }
    var paragrafos: ClosedRange<Int> { primeiroParagrafo...ultimoParagrafo }
}

enum CortadorDeTrechos {
    /// Duração-alvo de cada trecho: cerca de 5 minutos (Atlas, objeto Narração).
    static let duracaoAlvo: TimeInterval = 5 * 60

    /// Ritmo usado para estimar a duração antes de a voz existir.
    /// É uma estimativa técnica, a calibrar com a voz real da Inworld no teste de escuta.
    static var palavrasPorMinuto: Double = 150

    static var palavrasPorTrecho: Int { Int(duracaoAlvo / 60 * palavrasPorMinuto) }

    /// Corta o livro inteiro em trechos. O corte só depende do texto, então é sempre o mesmo
    /// para o mesmo livro: isso garante no máximo uma narração por trecho.
    /// O corte nunca acontece no meio de um parágrafo, mesmo que o parágrafo seja muito longo.
    static func cortar(_ texto: TextoDoLivro) -> [Trecho] {
        let alvo = palavrasPorTrecho
        var trechos: [Trecho] = []
        var inicio = 0
        var soma = 0
        for (i, p) in texto.paragrafos.enumerated() {
            soma += TextoDoLivro.contarPalavras(p.texto)
            if soma >= alvo {
                trechos.append(Trecho(indice: trechos.count, primeiroParagrafo: inicio, ultimoParagrafo: i, palavras: soma))
                inicio = i + 1
                soma = 0
            }
        }
        if inicio < texto.paragrafos.count {
            // Sobra muito curta no fim do livro (menos de um minuto) entra no trecho anterior.
            if let ultimo = trechos.last, soma < alvo / 5 {
                trechos[trechos.count - 1] = Trecho(indice: ultimo.indice, primeiroParagrafo: ultimo.primeiroParagrafo,
                                                     ultimoParagrafo: texto.paragrafos.count - 1, palavras: ultimo.palavras + soma)
            } else {
                trechos.append(Trecho(indice: trechos.count, primeiroParagrafo: inicio, ultimoParagrafo: texto.paragrafos.count - 1, palavras: soma))
            }
        }
        return trechos
    }

    /// O trecho que contém um parágrafo.
    static func trecho(doParagrafo p: Int, em trechos: [Trecho]) -> Trecho? {
        var baixo = 0, alto = trechos.count - 1
        while baixo <= alto {
            let meio = (baixo + alto) / 2
            if trechos[meio].ultimoParagrafo < p { baixo = meio + 1 }
            else if trechos[meio].primeiroParagrafo > p { alto = meio - 1 }
            else { return trechos[meio] }
        }
        return nil
    }
}
