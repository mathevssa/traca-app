import SwiftUI

/// Painel de velocidade (OUV-004): sobe da base em vidro, com o valor grande, os botões
/// de menos e mais, o slider com as seis paradas de 0,75x a 2x e os atalhos mais usados.
struct PainelDeVelocidade: View {
    let tocador: Tocador
    let fechar: () -> Void

    private let atalhos: [Float] = [1, 1.25, 1.5, 2]

    var body: some View {
        VStack(spacing: 14) {
            Capsule()
                .fill(Cor.texto.opacity(0.2))
                .frame(width: 36, height: 5)

            HStack {
                Text("Velocidade")
                    .font(Fonte.ui(20, .bold, relativoA: .title3))
                    .foregroundStyle(Cor.texto)
                Spacer()
                Button(action: fechar) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Paleta.neutro700)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Fechar")
                .padding(.trailing, -8)
            }

            HStack {
                botaoRedondo("minus", "Diminuir 0,25") { passo(-1) }
                Spacer()
                Text(Tocador.rotulo(tocador.velocidade))
                    .font(Fonte.ui(56, .bold, relativoA: .largeTitle))
                    .tracking(-1.1)
                    .monospacedDigit()
                    .foregroundStyle(Cor.texto)
                    .contentTransition(.numericText())
                Spacer()
                botaoRedondo("plus", "Aumentar 0,25") { passo(1) }
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)

            SliderDeVelocidade(valor: Binding(get: { tocador.velocidade }, set: { tocador.velocidade = $0 }))
                .padding(.horizontal, 18)
                .padding(.top, 4)

            HStack(spacing: 8) {
                ForEach(atalhos, id: \.self) { v in
                    let marcado = tocador.velocidade == v
                    Button { escolher(v) } label: {
                        Text(Tocador.rotulo(v))
                            .font(Fonte.ui(15, .semibold))
                            .foregroundStyle(marcado ? Cor.textoSobreAcao : Cor.texto)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 44)
                            .background(marcado ? Cor.acao : .clear, in: Capsule())
                            .overlay { if !marcado { Capsule().strokeBorder(Cor.borda) } }
                    }
                    .accessibilityAddTraits(marcado ? .isSelected : [])
                }
            }
            .padding(.top, 6)
        }
        .padding(EdgeInsets(top: 8, leading: 18, bottom: 22, trailing: 18))
        .vidroDePainel()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Velocidade")
    }

    private func botaoRedondo(_ icone: String, _ rotulo: String, _ acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            Image(systemName: icone)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Cor.texto)
                .frame(width: 52, height: 52)
                .background(Cor.texto.opacity(0.07), in: Circle())
        }
        .accessibilityLabel(rotulo)
    }

    private func passo(_ direcao: Int) {
        let lista = Tocador.velocidades
        let i = lista.firstIndex(of: tocador.velocidade) ?? 1
        escolher(lista[min(max(0, i + direcao), lista.count - 1)])
    }

    private func escolher(_ v: Float) {
        withAnimation(.snappy) { tocador.velocidade = v }
    }
}

/// Slider com as seis paradas da velocidade. Arrastar para entre duas paradas
/// encaixa na mais próxima, porque a velocidade só anda de 0,25x em 0,25x.
struct SliderDeVelocidade: View {
    @Binding var valor: Float
    private let paradas = Tocador.velocidades

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                let largura = geo.size.width
                let fracao = CGFloat(indice) / CGFloat(paradas.count - 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(Paleta.neutro300).frame(height: 4)
                    Capsule().fill(Cor.marca).frame(width: largura * fracao, height: 4)
                    ForEach(paradas.indices, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(i <= indice ? Cor.marca : Paleta.neutro400)
                            .frame(width: 4, height: paradas[i] == 1 ? 14 : 10)
                            .position(x: largura * CGFloat(i) / CGFloat(paradas.count - 1), y: 22)
                    }
                    Circle()
                        .fill(Cor.marca)
                        .frame(width: 24, height: 24)
                        .overlay(Circle().stroke(Paleta.laranja100, lineWidth: 4).padding(-2))
                        .position(x: largura * fracao, y: 22)
                }
                .frame(height: 44)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            let f = min(max(0, g.location.x / max(largura, 1)), 1)
                            let i = Int((f * CGFloat(paradas.count - 1)).rounded())
                            if paradas[i] != valor {
                                withAnimation(.snappy) { valor = paradas[i] }
                            }
                        }
                )
            }
            .frame(height: 44)
            .sensoryFeedback(.selection, trigger: valor)

            GeometryReader { geo in
                ForEach(paradas.indices, id: \.self) { i in
                    Text(Tocador.rotulo(paradas[i]))
                        .font(Fonte.ui(13, i == indice ? .bold : .medium, relativoA: .caption))
                        .foregroundStyle(i == indice ? Cor.link : Cor.textoSecundario)
                        .fixedSize()
                        .position(x: geo.size.width * CGFloat(i) / CGFloat(paradas.count - 1), y: 9)
                }
            }
            .frame(height: 18)
            .accessibilityHidden(true)
        }
        .accessibilityElement()
        .accessibilityLabel("Velocidade")
        .accessibilityValue(Tocador.rotulo(valor))
        .accessibilityAdjustableAction { direcao in
            let i = indice + (direcao == .increment ? 1 : -1)
            valor = paradas[min(max(0, i), paradas.count - 1)]
        }
    }

    private var indice: Int { paradas.firstIndex(of: valor) ?? 1 }
}
