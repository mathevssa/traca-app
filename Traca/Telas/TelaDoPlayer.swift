import StoreKit
import SwiftUI

/// Player (OUV-001 a OUV-017): o texto com a frase e a palavra faladas destacadas,
/// rolando sozinho, a barra de controles em vidro e os painéis de velocidade,
/// capítulos e marcações, vozes e timer.
struct TelaDoPlayer: View {
    let tocador: Tocador
    @Environment(\.dismiss) private var fechar
    @Environment(EstadoDoApp.self) private var app
    @State private var seguindoAVoz = true
    @State private var painel: PainelDoPlayer?
    @State private var aviso: AvisoDoPlayer?
    @State private var tarefaDoAviso: Task<Void, Never>?
    @State private var atualizandoPagamento = false

    private var livro: LivroGuardado? { app.livroDoTocador }

    var body: some View {
        ScrollViewReader { rolagem in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(Array(tocador.texto.paragrafos.enumerated()), id: \.offset) { i, p in
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
                .padding(.bottom, 300)
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
                if tocador.estado == .parado { tocador.comecarDaPosicaoSalva() }
            }
            .overlay(alignment: .bottom) {
                VStack(spacing: 12) {
                    if !seguindoAVoz {
                        // OUV-003: a pílula para voltar ao ponto da voz.
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
                    if let aviso = app.avisoNoPlayer {
                        // IMP-004: o livro já estava na biblioteca, e é ele que abre.
                        AvisoFlutuante(texto: aviso.texto, icone: "books.vertical") { app.avisoNoPlayer = nil }
                            .padding(.horizontal, 6)
                    }
                    if let aviso {
                        AvisoFlutuante(texto: aviso.texto, icone: aviso.icone) { self.aviso = nil }
                            .padding(.horizontal, 6)
                    }
                    if app.avisoDoTeto {
                        // PROPOSTA de texto, a aprovar pelo Matheus: o Atlas não tem a mensagem do teto do teste.
                        AvisoFlutuante(texto: "Você usou as 3 horas de voz do teste grátis. O que já foi preparado continua tocando, e o resto do livro volta quando a assinatura começar.", icone: "hourglass") {
                            app.avisoDoTeto = false
                        }
                        .padding(.horizontal, 6)
                    }
                    if app.avisoDeCarencia { avisoDeCarencia }
                    if tocador.estado == .erro { avisoDeErro }
                    BarraDoPlayer(tocador: tocador, nomeDaVoz: nomeDaVoz, marcar: marcar) { painel in
                        withAnimation(.spring(duration: 0.35)) { self.painel = painel }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                .animation(.snappy, value: aviso)
            }
        }
        .background(Cor.fundo)
        .safeAreaInset(edge: .top) { topo }
        .overlay {
            if tocador.estado == .fim { fimDoLivro }
        }
        .overlay { paineis }
        .onDisappear { app.avisoNoPlayer = nil }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Topo

    private var topo: some View {
        VStack(spacing: 8) {
            cabecalho
            if app.acesso == .antesDoTeste { contadorGratis }
        }
        .padding(.bottom, 4)
        .background(Cor.fundo.opacity(0.92))
    }

    /// CMC-005 e CMC-007: quanto falta dos 5 minutos grátis, ou o aviso de que acabaram.
    private var contadorGratis: some View {
        let m = app.minutosGratis
        let fracao = min(m.tocados / MinutosGratis.limite, 1)
        return HStack(spacing: 10) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Cor.textoSecundario.opacity(0.25))
                    Capsule().fill(m.acabaram ? Cor.textoSecundario : Cor.marca).frame(width: g.size.width * fracao)
                }
            }
            .frame(width: 44, height: 4)
            Text(m.acabaram ? "Os 5 minutos grátis acabaram" : "Faltam \(FormatoDeTempo.relogio(m.restantes)) dos 5 minutos grátis")
                .font(Fonte.ui(13, .semibold, relativoA: .caption))
                .monospacedDigit()
                .foregroundStyle(Cor.texto)
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .glassEffect(.regular, in: Capsule())
        .accessibilityElement(children: .combine)
    }

    /// ASS-003: a cobrança não passou; o leitor ouve o que já foi gerado durante a carência.
    private var avisoDeCarencia: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "creditcard").foregroundStyle(Cor.alerta)
            VStack(alignment: .leading, spacing: 4) {
                Text("Não conseguimos renovar sua assinatura").font(Fonte.ui(15, .semibold)).foregroundStyle(Cor.texto)
                Text("Houve um problema com o pagamento. Para continuar ouvindo o livro, atualize a forma de pagamento.")
                    .font(Fonte.ui(14, relativoA: .subheadline)).foregroundStyle(Paleta.neutro700)
                Button { atualizandoPagamento = true } label: {
                    HStack(spacing: 6) {
                        Text("Atualizar pagamento nos Ajustes")
                        Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .semibold))
                    }
                    .font(Fonte.ui(14, .semibold, relativoA: .subheadline))
                    .foregroundStyle(Cor.link)
                    .frame(minHeight: 36)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color(hex: 0xF8E7C4), in: RoundedRectangle(cornerRadius: 16))
        .manageSubscriptionsSheet(isPresented: $atualizandoPagamento)
    }

    private var cabecalho: some View {
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
                if let cap = NomesDeCapitulo.cabecalho(tocador.texto, capitulo: tocador.capituloAtual) {
                    Text(cap)
                        .font(Fonte.caption)
                        .foregroundStyle(Cor.textoSecundario)
                        .lineLimit(1)
                }
            }
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 12)
    }

    // MARK: Painéis

    @ViewBuilder private var paineis: some View {
        if let painel {
            ZStack(alignment: .bottom) {
                Escurecimento { fecharPainel() }
                Group {
                    switch painel {
                    case .velocidade:
                        PainelDeVelocidade(tocador: tocador, fechar: fecharPainel)
                    case .capitulos(let aba):
                        PainelDeCapitulos(tocador: tocador, livro: livro, abaInicial: aba, fechar: fecharPainel) { p, local in
                            fecharPainel()
                            seguindoAVoz = true
                            tocador.tocar(aPartirDoParagrafo: p, local: local)
                        } excluirMarcacao: { m in
                            if let id = livro?.id { app.biblioteca.excluirMarcacao(id, m.id) }
                        }
                    case .vozes:
                        PainelDeVozes(tocador: tocador, fechar: fecharPainel) { id in
                            EstadoDoApp.idDaVozEscolhida = id
                            fecharPainel()
                            // OUV-006: a voz nova só entra no próximo capítulo.
                            if tocador.trocarVoz(id) { mostrar(.vozNoProximoCapitulo) }
                        }
                    case .timer:
                        PainelDeTimer(tocador: tocador, fechar: fecharPainel)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                .padding(.top, painel.ocupaATela ? 150 : 0)
                .gesture(DragGesture().onEnded { if $0.translation.height > 60 { fecharPainel() } })
                .transition(.move(edge: .bottom))
            }
        }
    }

    private func fecharPainel() {
        withAnimation(.spring(duration: 0.3)) { painel = nil }
    }

    private var nomeDaVoz: String {
        VozDoIPhone().vozes.first { $0.id == tocador.idDaVozEscolhida }?.nome ?? ""
    }

    // MARK: Marcar e avisos

    /// Marcar salva o ponto atual na hora, sem pedir confirmação, e mostra "Marcação salva".
    private func marcar() {
        guard let id = livro?.id else { return }
        app.biblioteca.marcar(id, tocador.posicaoAtual, capitulo: tocador.capituloAtual)
        mostrar(.marcacaoSalva)
    }

    private func mostrar(_ novo: AvisoDoPlayer) {
        aviso = novo
        tarefaDoAviso?.cancel()
        tarefaDoAviso = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { aviso = nil }
        }
    }

    /// OUV-016: o livro acabou. Na biblioteca ele passa a mostrar "Terminado".
    private var fimDoLivro: some View {
        ZStack(alignment: .bottom) {
            Escurecimento {}
            VStack(spacing: 18) {
                CapaDoLivro(titulo: tocador.livro.titulo ?? "", imagem: tocador.livro.capa.flatMap(UIImage.init(data:)), raio: 8, tamanhoDoTitulo: 10)
                    .frame(width: 72, height: 104)
                Text("Você terminou \(tocador.livro.titulo ?? "")")
                    .font(Fonte.marca(28, relativoA: .title))
                    .tracking(-0.56)
                    .foregroundStyle(Cor.texto)
                    .multilineTextAlignment(.center)
                VStack(spacing: 10) {
                    BotaoPrincipal(titulo: "Voltar para a biblioteca") { fechar() }
                    Button {
                        if let id = app.livroDoTocador?.id { app.biblioteca.recomecar(id) }
                        tocador.tocar(aPartirDoParagrafo: 0)
                    } label: {
                        Text("Ouvir de novo")
                            .font(Fonte.headline)
                            .foregroundStyle(Cor.texto)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(.white.opacity(0.55), in: Capsule())
                            .overlay(Capsule().strokeBorder(Cor.texto.opacity(0.08)))
                    }
                }
                .padding(.top, 4)
            }
            .padding(EdgeInsets(top: 26, leading: 20, bottom: 20, trailing: 20))
            .vidroDePainel()
            .padding(8)
            .accessibilityAddTraits(.isModal)
        }
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

/// Os painéis que sobem da base no player.
enum PainelDoPlayer: Equatable {
    case velocidade
    case capitulos(PainelDeCapitulos.Aba)
    case vozes
    case timer

    /// Capítulos e marcações ocupam quase a tela toda (OUV-007).
    var ocupaATela: Bool { if case .capitulos = self { true } else { false } }
}

/// Avisos curtos que aparecem por cima da barra e somem sozinhos.
enum AvisoDoPlayer: Equatable {
    case marcacaoSalva
    case vozNoProximoCapitulo

    var texto: String {
        switch self {
        case .marcacaoSalva: "Marcação salva"
        case .vozNoProximoCapitulo: "A nova voz começa no próximo capítulo."
        }
    }

    var icone: String {
        switch self {
        case .marcacaoSalva: "bookmark.fill"
        case .vozNoProximoCapitulo: "waveform"
        }
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
