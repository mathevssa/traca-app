import SwiftUI

/// Player da Fase 0, a partir do OUV-001 do canvas: o texto com a frase e a palavra faladas
/// destacadas, rolando sozinho, e a barra de controles em vidro.
/// Voz, capítulos, marcações e timer entram na Fase 2.
struct TelaDoPlayer: View {
    let tocador: Tocador
    @Environment(\.dismiss) private var fechar
    @State private var seguindoAVoz = true
    @State private var mostrandoVelocidade = false

    var body: some View {
        ScrollViewReader { rolagem in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(Array(tocador.livro.texto.paragrafos.enumerated()), id: \.offset) { i, p in
                        // Tocar numa frase leva a voz para o começo dela (fluxo Ouvir um livro).
                        ParagrafoView(paragrafo: p, estado: estado(de: i)) { local in
                            seguindoAVoz = true
                            tocador.tocar(aPartirDoParagrafo: i, local: local)
                        }
                        .id(i)
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
                    BarraDoPlayer(tocador: tocador) {
                        withAnimation(.spring(duration: 0.35)) { mostrandoVelocidade = true }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
        .background(Cor.fundo)
        .safeAreaInset(edge: .top) { topo }
        .overlay {
            // Painel de velocidade (OUV-004) por cima do player, com o fundo levemente escurecido.
            if mostrandoVelocidade {
                ZStack(alignment: .bottom) {
                    Cor.texto.opacity(0.18)
                        .ignoresSafeArea()
                        .onTapGesture { fecharVelocidade() }
                        .accessibilityHidden(true)
                        .transition(.opacity)
                    PainelDeVelocidade(tocador: tocador, fechar: fecharVelocidade)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 10)
                        .gesture(DragGesture().onEnded { if $0.translation.height > 60 { fecharVelocidade() } })
                        .transition(.move(edge: .bottom))
                }
            }
        }
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

    private func fecharVelocidade() {
        withAnimation(.spring(duration: 0.3)) { mostrandoVelocidade = false }
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
    /// Recebe a posição (dentro do parágrafo) do começo da frase tocada.
    var aoTocarFrase: (Int) -> Void = { _ in }

    static func == (a: ParagrafoView, b: ParagrafoView) -> Bool {
        a.paragrafo == b.paragrafo && a.estado == b.estado
    }

    var body: some View {
        if paragrafo.tipo == .titulo {
            Text(paragrafo.texto)
                .font(Fonte.marca(24, relativoA: .title2))
                .tracking(-0.48)
                .foregroundStyle(Cor.textoSecundario)
                .padding(.top, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { aoTocarFrase(0) }
        } else {
            textoPorFrases
                .font(Fonte.leitura)
                .lineSpacing(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                // O iOS informa onde cada pedaço do texto foi desenhado; com isso, o toque
                // vira a frase que estava debaixo do dedo.
                .overlayPreferenceValue(Text.LayoutKey.self) { desenhos in
                    GeometryReader { geo in
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { ponto in
                                aoTocarFrase(frase(em: ponto, desenhos: desenhos, geo: geo) ?? 0)
                            }
                    }
                }
        }
    }

    /// O parágrafo montado frase por frase, cada uma marcada com onde ela começa.
    private var textoPorFrases: Text {
        let estilizado = textoComDestaque
        let texto = paragrafo.texto
        let total = (texto as NSString).length
        var inicios = paragrafo.frases.map(\.location).filter { $0 < total }
        if inicios.first != 0 { inicios.insert(0, at: 0) }
        var resultado = Text("")
        for (k, inicio) in inicios.enumerated() {
            let fim = k + 1 < inicios.count ? inicios[k + 1] : total
            guard fim > inicio, let rs = Range(NSRange(location: inicio, length: fim - inicio), in: texto),
                  let ra = Range(rs, in: estilizado) else { continue }
            let pedaco = Text(AttributedString(estilizado[ra])).customAttribute(InicioDaFrase(local: inicio))
            resultado = Text("\(resultado)\(pedaco)")
        }
        return resultado
    }

    /// Acha a frase desenhada no ponto tocado. Toque no espaço entre linhas vai para a frase mais perto.
    private func frase(em ponto: CGPoint, desenhos: Text.LayoutKey.Value, geo: GeometryProxy) -> Int? {
        var melhor: (distancia: CGFloat, local: Int)?
        for d in desenhos {
            let origem = geo[d.origin]
            for linha in d.layout {
                for pedaco in linha {
                    guard let marca = pedaco[InicioDaFrase.self] else { continue }
                    let r = pedaco.typographicBounds.rect.offsetBy(dx: origem.x, dy: origem.y)
                    let dx = max(r.minX - ponto.x, 0, ponto.x - r.maxX)
                    let dy = max(r.minY - ponto.y, 0, ponto.y - r.maxY)
                    let distancia = dy * 4 + dx // a linha certa importa mais que a coluna
                    if distancia == 0 { return marca.local }
                    if melhor == nil || distancia < melhor!.distancia { melhor = (distancia, marca.local) }
                }
            }
        }
        return melhor?.local
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

/// Marca invisível em cada frase do texto: onde ela começa dentro do parágrafo.
struct InicioDaFrase: TextAttribute {
    let local: Int
}

/// Barra de controles em vidro (OUV-001): progresso, velocidade, voltar 15, play, avançar 15.
struct BarraDoPlayer: View {
    let tocador: Tocador
    let abrirVelocidade: () -> Void

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
                Button(action: abrirVelocidade) {
                    HStack(spacing: 4) {
                        Image(systemName: "gauge.with.needle")
                            .font(.system(size: 14, weight: .semibold))
                        Text(Tocador.rotulo(tocador.velocidade))
                            .font(Fonte.ui(15, .semibold))
                            .monospacedDigit()
                    }
                    .foregroundStyle(Cor.texto)
                    .padding(.horizontal, 10)
                    .frame(minWidth: 60, minHeight: 44)
                    .background(.white.opacity(0.55), in: Capsule())
                }
                .accessibilityLabel("Velocidade: \(Tocador.rotulo(tocador.velocidade).replacingOccurrences(of: "x", with: " vez"))")
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

    private func tempo(_ s: TimeInterval) -> String {
        let t = Int(s.isFinite ? s : 0)
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}
