import SwiftUI

/// Tela provisória da Fase 0. Mostra a marca e o título de Boas-vindas (CMC-001)
/// para provar que o projeto, as fontes e as cores estão certos.
/// Será trocada pela tela de teste da voz nas próximas etapas.
struct TelaInicial: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Logotipo()
            VStack(alignment: .leading, spacing: 12) {
                Text("Seus livros, lidos em voz alta.")
                    .font(Fonte.marca(34))
                    .tracking(-0.68)
                    .foregroundStyle(Cor.texto)
                Text("Escolha um ebook que você já tem e ouça com o texto acompanhando a voz.")
                    .font(Fonte.body)
                    .foregroundStyle(Paleta.neutro700)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Cor.fundo)
    }
}

#Preview {
    TelaInicial()
}
