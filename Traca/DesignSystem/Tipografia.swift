import SwiftUI

// Tipografia do quadro DS-01. Young Serif para a marca e títulos de livro,
// Hanken Grotesk para a interface. Os tamanhos acompanham o Dynamic Type.

enum Fonte {
    static func marca(_ tamanho: CGFloat, relativoA estilo: Font.TextStyle = .largeTitle) -> Font {
        .custom("YoungSerif-Regular", size: tamanho, relativeTo: estilo)
    }

    static func ui(_ tamanho: CGFloat, _ peso: Font.Weight = .regular, relativoA estilo: Font.TextStyle = .body) -> Font {
        .custom("Hanken Grotesk", size: tamanho, relativeTo: estilo).weight(peso)
    }

    static let display = ui(34, .bold, relativoA: .largeTitle)
    static let title1 = ui(28, .semibold, relativoA: .title)
    static let title2 = ui(22, .semibold, relativoA: .title2)
    static let headline = ui(17, .semibold, relativoA: .headline)
    static let body = ui(17, relativoA: .body)
    static let callout = ui(15, relativoA: .callout)
    static let caption = ui(13, .medium, relativoA: .caption)
    static let leitura = ui(22, relativoA: .body)
    static let tituloLivro = marca(28, relativoA: .title)
}
