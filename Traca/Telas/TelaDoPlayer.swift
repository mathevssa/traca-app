import SwiftUI

/// Player da Fase 0, a partir do OUV-001 do canvas: o texto com a frase e a palavra faladas
/// destacadas, rolando sozinho, e a barra de controles em vidro.
/// Voz, capítulos, marcações e timer entram na Fase 2.
struct TelaDoPlayer: View {
    let tocador: Tocador
    @Environment(\.dismiss) private var fechar
    @State private var seguindoAVoz = true

    var body: some View {
        ScrollViewReader { rolagem in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(Array(tocador.livro.texto.paragrafos.enumerated()), id: \.offset) { i, p in
                        ParagrafoView(paragrafo: p, estado: estado(de: i))
                            .id(i)
                            .contentShape(Rectangle())
                            // Tocar num parágrafo leva a voz para o começo dele.
                            .onTapGesture {
                                seguindoAVoz = true
                                tocador.tocar(aPartirDoParagrafo: i)
                            }
                    }
                }
                .padding(.horizontal, 26)
                .padding(.top, 6)
                .padding(.bottom, 260)
            }
            .scrollIndicators(.hidden)
            .onScrollPhaseChange { _, nova in
                // O leitor rolou com o dedo: a rolagem automática para (fluxo Ouvir um livro).
                if nova == .interacting { seguindoAVoz = false }
            }
            .onChange(of: tocador.paragrafoAtual) { _, p in
                guard seguindoAVoz else { return }
                withAnimation(.easeInOut(duration: 0.4)) { rolagem.scrollTo(p, anchor: UnitPoint(x: 0, y: 0.3)) }
            }
            .onAppear {
                rolagem.scrollTo(tocador.paragrafoAtual, anchor: UnitPoint(x: 0, y: 0.3))
                if tocador.estado == .parado { tocador.tocar(aPartirDoParagrafo: tocador.paragrafoAtual) }
            }
            .overlay(alignment: .bottom) {
                VStack(spacing: 12) {
                    if !seguindoAVoz {
                        Button {
                            seguindoAVoz = true
                            withAnimation { rolagem.scrollTo(tocador.paragrafoAtual, anchor: UnitPoint(x: 0, y: 0.3)) }
                        } label: {
                            Text("Voltar para onde estou")
                                .font(Fonte.ui(15, .semibold))
                                .foregroundStyle(Cor.texto)
                                .padding(.horizontal, 18)
                                .frame(minHeight: 44)
                        }
                        .glassEffect(.regular, in: Capsule())
                    }
                    if tocador.estado == .erro { avisoDeErro }
                    BarraDoPlayer(tocador: tocador)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
        .background(Cor.fundo)
        .safeAreaInset(edge: .top) { topo }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var topo: some View {
        HStack {
            Button { fechar() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Cor.texto)
                    .frame(width: 44, height: 44)
            }
            .glassEffect(.regular, in: Circle())
            .accessibilityLabel("Voltar para a biblioteca")
            Spacer()
            VStack(spacing: 2) {
                Text(tocador.livro.titulo ?? "")
                    .font(Fonte.marca(17, relativoA: .headline))
                    .foregroundStyle(Cor.texto)
                    .lineLimit(1)
                Text(tituloDoCapitulo)
                    .font(Fonte.caption)
                    .foregroundStyle(Cor.textoSecundario)
                    .lineLimit(1)
            }
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        .background(Cor.fundo.opacity(0.92))
    }

    private var tituloDoCapitulo: String {
        let t = tocador.livro.texto
        return t.capitulos[t.capitulo(em: Posicao(paragrafo: tocador.paragrafoAtual, deslocamento: 0))].titulo
    }

    /// Texto e botão de OUV-011 (fluxo Ouvir um livro, Estados de UI).
    private var avisoDeErro: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Não deu para preparar a voz deste trecho agora.")
                .font(Fonte.body)
                .foregroundStyle(Cor.texto)
            Button("Tentar de novo") { tocador.tentarDeNovo() }
                .font(Fonte.headline)
                .foregroundStyle(Cor.link)
                .frame(minHeight: 44)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
    }

    private func estado(de i: Int) -> ParagrafoView.Estado {
        if i < tocador.paragrafoAtual { return .lido }
        if i > tocador.paragrafoAtual { return .aLer }
        return .atual(tocador.palavraAtual?.paragrafo == i ? tocador.palavraAtual : nil)
    }
}

/// Um parágrafo do livro. Só o parágrafo da voz muda a cada palavra; os outros ficam parados,
/// o que mantém a rolagem leve mesmo em livros com milhares de parágrafos.
struct ParagrafoView: View, Equatable {
    enum Estado: Equatable { case lido, aLer, atual(MarcaDeTempo?) }

    let paragrafo: Paragrafo
    let estado: Estado

    var body: some View {
        if paragrafo.tipo == .titulo {
            Text(paragrafo.texto)
                .font(Fonte.marca(24, relativoA: .title2))
                .tracking(-0.48)
                .foregroundStyle(Cor.textoSecundario)
                .padding(.top, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(textoComDestaque)
                .font(Fonte.leitura)
                .lineSpacing(12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// No parágrafo atual: o que já foi lido fica mais claro, a frase falada ganha fundo
    /// laranja-claro e a palavra falada fica em laranja e negrito (OUV-001).
    private var textoComDestaque: AttributedString {
        var a = AttributedString(paragrafo.texto)
        switch estado {
        case .lido:
            a.foregroundColor = Cor.leituraFeita
        case .aLer, .atual(nil):
            a.foregroundColor = Cor.texto
        case .atual(let marca?):
            a.foregroundColor = Cor.texto
            let s = paragrafo.texto as NSString
            let frase = paragrafo.frases.first { NSLocationInRange(marca.local, $0) }
                ?? NSRange(location: marca.local, length: marca.tamanho)
            if let antes = Range(NSRange(location: 0, length: frase.location), in: paragrafo.texto),
               let r = Range(antes, in: a) {
                a[r].foregroundColor = Cor.leituraFeita
            }
            if let rf = Range(frase, in: paragrafo.texto), let r = Range(rf, in: a) {
                a[r].backgroundColor = Cor.leituraFrase
            }
            let palavra = NSRange(location: marca.local, length: min(marca.tamanho, s.length - marca.local))
            if let rp = Range(palavra, in: paragrafo.texto), let r = Range(rp, in: a) {
                a[r].foregroundColor = Cor.leituraPalavra
                a[r].font = Fonte.ui(22, .bold)
            }
        }
        return a
    }
}

/// Barra de controles em vidro (OUV-001): progresso, velocidade, voltar 15, play, avançar 15.
struct BarraDoPlayer: View {
    let tocador: Tocador

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 8) {
                ProgressView(value: min(tocador.tempoNoTrecho, max(tocador.duracaoDoTrecho, 0.01)),
                             total: max(tocador.duracaoDoTrecho, 0.01))
                    .tint(Cor.progresso)
                HStack {
                    Text(tempo(tocador.tempoNoTrecho))
                    Spacer()
                    if tocador.estado == .preparando {
                        Text("Preparando a voz")
                    }
                }
                .font(Fonte.caption)
                .foregroundStyle(Cor.textoSecundario)
                .monospacedDigit()
            }
            .padding(.horizontal, 6)

            HStack {
                Button { trocarVelocidade() } label: {
                    Text(velocidadeTexto)
                        .font(Fonte.ui(15, .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Cor.texto)
                        .frame(minWidth: 60, minHeight: 44)
                        .background(.white.opacity(0.55), in: Capsule())
                }
                .accessibilityLabel("Velocidade: \(velocidadeTexto)")
                Spacer()
                botaoDeSalto("gobackward.15", "Voltar 15 segundos") { tocador.pular(-15) }
                Spacer()
                Button { tocador.alternar() } label: {
                    ZStack {
                        Circle().fill(Cor.play)
                        if tocador.estado == .preparando {
                            ProgressView().tint(Cor.creme)
                        } else {
                            Image(systemName: tocador.estado == .tocando ? "pause.fill" : "play.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(Cor.creme)
                        }
                    }
                    .frame(width: 76, height: 76)
                    .shadow(color: Cor.marca.opacity(0.35), radius: 12, y: 8)
                }
                .accessibilityLabel(tocador.estado == .tocando ? "Pausar" : "Tocar")
                Spacer()
                botaoDeSalto("goforward.15", "Avançar 15 segundos") { tocador.pular(15) }
                Spacer()
                Color.clear.frame(width: 60, height: 44)
            }
            .padding(.horizontal, 4)
        }
        .padding(EdgeInsets(top: 16, leading: 12, bottom: 12, trailing: 12))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 32))
    }

    private func botaoDeSalto(_ icone: String, _ rotulo: String, _ acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            Image(systemName: icone)
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(Cor.texto)
                .frame(width: 52, height: 52)
        }
        .accessibilityLabel(rotulo)
    }

    private var velocidadeTexto: String {
        let v = tocador.velocidade
        let texto = v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v).replacingOccurrences(of: "0$", with: "", options: .regularExpression)
        return texto.replacingOccurrences(of: ".", with: ",") + "x"
    }

    private func trocarVelocidade() {
        let lista = Tocador.velocidades
        let i = lista.firstIndex(of: tocador.velocidade) ?? 1
        tocador.velocidade = lista[(i + 1) % lista.count]
    }

    private func tempo(_ s: TimeInterval) -> String {
        let t = Int(s.isFinite ? s : 0)
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}
