import SwiftUI

// Paleta e cores semânticas do canvas: Brandbook 05 e quadro DS-01.
// As telas usam só os nomes semânticos (Cor.texto, Cor.acao...), nunca a paleta direto.

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

enum Paleta {
    static let neutro50 = Color(hex: 0xFFF8F1)
    static let neutro100 = Color(hex: 0xFFF1E3) // creme
    static let neutro200 = Color(hex: 0xF5E3D0)
    static let neutro300 = Color(hex: 0xE6CFB9)
    static let neutro400 = Color(hex: 0xC9AE96)
    static let neutro500 = Color(hex: 0x9E8470)
    static let neutro600 = Color(hex: 0x7A6352)
    static let neutro700 = Color(hex: 0x4F3D32)
    static let neutro800 = Color(hex: 0x2E221B)
    static let neutro900 = Color(hex: 0x1C1410)

    static let laranja100 = Color(hex: 0xFBE0D2)
    static let laranja200 = Color(hex: 0xF6BFA3)
    static let laranja300 = Color(hex: 0xEE8450)
    static let laranja500 = Color(hex: 0xD9541E) // marca
    static let laranja600 = Color(hex: 0xB8441A)
    static let laranja700 = Color(hex: 0xA33C10)
    static let laranja800 = Color(hex: 0x7E2E0C)
}

/// Cores semânticas do modo claro (o MVP é sempre claro).
enum Cor {
    static let marca = Paleta.laranja500
    static let creme = Paleta.neutro100

    static let fundo = Paleta.neutro100
    static let fundoElevado = Paleta.neutro50
    static let fundoSutil = Paleta.neutro200
    static let borda = Paleta.neutro300

    static let texto = Paleta.neutro900
    static let textoSecundario = Paleta.neutro600
    static let textoDesativado = Paleta.neutro400
    static let link = Paleta.laranja700
    static let textoSobreAcao = Paleta.neutro100

    static let acao = Paleta.laranja600
    static let acaoPressionada = Paleta.laranja700
    static let acaoDesativada = Paleta.neutro300

    static let play = Paleta.laranja500
    static let progresso = Paleta.laranja500

    /// Fundo da frase que está sendo lida.
    static let leituraFrase = Paleta.laranja200
    /// A palavra falada, dentro da frase destacada (OUV-001).
    static let leituraPalavra = Paleta.laranja600
    /// Texto que a voz já leu.
    static let leituraFeita = Paleta.neutro600

    static let sucesso = Color(hex: 0x3F6528)
    static let alerta = Color(hex: 0x8A5A10)
    static let erro = Color(hex: 0xB3261E)
}
