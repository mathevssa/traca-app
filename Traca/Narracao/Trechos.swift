import Foundation

/// O pedaço do livro que vai para a voz (objeto Narração, atributo Trecho).
/// Começa onde a voz vai tocar e termina perto dos 5 minutos, no fim de um parágrafo
/// ou na virada de capítulo, o que vier antes.
nonisolated struct Trecho: Codable, Hashable, Identifiable {
    /// Onde a voz começa: o parágrafo e a letra dentro dele.
    let inicio: Posicao
    /// Último parágrafo do trecho, incluído.
    let ultimoParagrafo: Int
    let palavras: Int

    var id: Posicao { inicio }
    var primeiroParagrafo: Int { inicio.paragrafo }
    var paragrafos: ClosedRange<Int> { inicio.paragrafo...ultimoParagrafo }

    /// Se uma posição do livro está dentro deste trecho.
    func contem(_ p: Posicao) -> Bool {
        p >= inicio && p.paragrafo <= ultimoParagrafo
    }
}

nonisolated enum CortadorDeTrechos {
    /// Duração-alvo de cada trecho: cerca de 5 minutos (Atlas, objeto Narração).
    static let duracaoAlvo: TimeInterval = 5 * 60

    /// Ritmo usado para estimar a duração antes de a voz existir.
    /// É uma estimativa técnica, a calibrar com a voz real da Inworld no teste de escuta.
    static let palavrasPorMinuto: Double = 150

    static var palavrasPorTrecho: Int { Int(duracaoAlvo / 60 * palavrasPorMinuto) }

    /// O trecho que começa numa posição: vai juntando parágrafos até passar dos 5 minutos
    /// e para antes do começo de um capítulo novo. Nunca corta no meio de um parágrafo.
    static func trecho(aPartirDe inicio: Posicao, em texto: TextoDoLivro) -> Trecho? {
        let total = texto.paragrafos.count
        guard inicio.paragrafo >= 0, inicio.paragrafo < total else { return nil }
        let comecosDeCapitulo = Set(texto.capitulos.map(\.primeiroParagrafo))
        var soma = 0
        var i = inicio.paragrafo
        while true {
            let t = texto.paragrafos[i].texto
            if i == inicio.paragrafo {
                let ns = t as NSString
                soma += TextoDoLivro.contarPalavras(ns.substring(from: min(max(0, inicio.deslocamento), ns.length)))
            } else {
                soma += TextoDoLivro.contarPalavras(t)
            }
            let proximo = i + 1
            if proximo >= total || soma >= palavrasPorTrecho || comecosDeCapitulo.contains(proximo) { break }
            i = proximo
        }
        return Trecho(inicio: inicio, ultimoParagrafo: i, palavras: soma)
    }

    /// O trecho que vem logo depois de outro, começando no parágrafo seguinte.
    static func proximo(depoisDe trecho: Trecho, em texto: TextoDoLivro) -> Trecho? {
        self.trecho(aPartirDe: Posicao(paragrafo: trecho.ultimoParagrafo + 1, deslocamento: 0), em: texto)
    }
}
