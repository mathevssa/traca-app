import SwiftUI

// Componentes do design system usados em várias telas (quadros DS-02 e DS-03 do canvas).

/// Capa do livro. Sem capa no arquivo, o app gera uma com o título em Young Serif
/// sobre o Laranja-queimado (objeto Livro, atributo Capa).
struct CapaDoLivro: View {
    let titulo: String
    let imagem: UIImage?
    var raio: CGFloat = 10
    var tamanhoDoTitulo: CGFloat = 19

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let imagem {
                // A imagem preenche o quadro da capa sem esticar o quadro.
                Color.clear.overlay {
                    Image(uiImage: imagem)
                        .resizable()
                        .scaledToFill()
                }
            } else {
                Cor.marca
                Text(titulo)
                    .font(Fonte.marca(tamanhoDoTitulo))
                    .tracking(-0.02 * tamanhoDoTitulo)
                    .foregroundStyle(Cor.creme)
                    .lineLimit(4)
                    .minimumScaleFactor(0.6)
                    .padding(tamanhoDoTitulo * 0.63)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: raio, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: raio, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Barra fina de progresso (cards da biblioteca e mini player).
struct BarraDeProgresso: View {
    let fracao: Double
    var altura: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Paleta.neutro300)
                Capsule().fill(Cor.marca).frame(width: geo.size.width * min(max(fracao, 0), 1))
            }
        }
        .frame(height: altura)
        .accessibilityHidden(true)
    }
}

/// Botão principal: cápsula em laranja.600 com texto creme e o brilho do vidro (DS-02).
struct BotaoPrincipal: View {
    let titulo: String
    var icone: String?
    var carregando = false
    let acao: () -> Void

    var body: some View {
        Button(action: acao) {
            HStack(spacing: 10) {
                if carregando {
                    ProgressView().tint(Cor.textoSobreAcao)
                } else if let icone {
                    Image(systemName: icone).font(.system(size: 18, weight: .semibold))
                }
                Text(titulo)
            }
            .font(Fonte.headline)
            .foregroundStyle(Cor.textoSobreAcao)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Cor.acao, in: Capsule())
            .shadow(color: Cor.marca.opacity(0.35), radius: 12, y: 8)
        }
    }
}

/// Título pequeno em caixa alta, como "CONTINUAR OUVINDO" (type.overline do DS-01).
struct Sobretitulo: View {
    let texto: String
    var cor: Color = Cor.textoSecundario

    var body: some View {
        Text(texto.uppercased())
            .font(Fonte.ui(11, .semibold, relativoA: .caption2))
            .tracking(0.88)
            .foregroundStyle(cor)
    }
}

/// Aviso flutuante em vidro (toast). Fica até o leitor tocar nele.
struct AvisoFlutuante: View {
    let texto: String
    var icone = "exclamationmark.circle"
    let fechar: () -> Void

    var body: some View {
        Button(action: fechar) {
            HStack(spacing: 12) {
                Image(systemName: icone)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Cor.link)
                Text(texto)
                    .font(Fonte.ui(14, relativoA: .subheadline))
                    .foregroundStyle(Cor.texto)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(EdgeInsets(top: 13, leading: 14, bottom: 13, trailing: 16))
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isStaticText)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// Fundo levemente escurecido atrás de painéis e diálogos (scrim.sheet do DS-01).
struct Escurecimento: View {
    let tocar: () -> Void
    var body: some View {
        Cor.texto.opacity(0.18)
            .ignoresSafeArea()
            .onTapGesture(perform: tocar)
            .accessibilityHidden(true)
            .transition(.opacity)
    }
}

extension View {
    /// Vidro dos painéis e diálogos (glass.light do DS-01, com creme a 75–78%): mais encorpado
    /// que o vidro da barra, para o texto do painel não brigar com o que está por baixo.
    func vidroDePainel(raio: CGFloat = 34) -> some View {
        background(Paleta.neutro50.opacity(0.86), in: RoundedRectangle(cornerRadius: raio, style: .continuous))
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: raio, style: .continuous))
    }
}
