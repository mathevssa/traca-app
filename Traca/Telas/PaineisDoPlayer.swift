import SwiftUI

// Barra de controles e painéis do player: Capítulos e Marcações (OUV-007 a OUV-009, OUV-017),
// Vozes (OUV-005) e Timer de sono (OUV-010, OUV-013). O painel de velocidade (OUV-004)
// fica em PainelDeVelocidade.swift.

// MARK: - Nomes e tempos

enum NomesDeCapitulo {
    /// Os capítulos com título, numerados a partir de 1. A parte sem título antes do primeiro
    /// capítulo (folha de rosto) não entra na lista.
    static func listados(_ texto: TextoDoLivro) -> [(indice: Int, numero: Int, titulo: String)] {
        var n = 0
        return texto.capitulos.enumerated().compactMap { i, c in
            guard !c.titulo.isEmpty else { return nil }
            n += 1
            return (i, n, limpo(c.titulo))
        }
    }

    /// "I · Do titulo." vira "Do titulo.": o número já aparece na lista.
    static func limpo(_ titulo: String) -> String {
        if let r = titulo.range(of: #"^[IVXLCDM]+ · "#, options: .regularExpression) {
            return String(titulo[r.upperBound...])
        }
        return titulo
    }

    /// "Cap. 3 · A denúncia", como no topo do player.
    static func cabecalho(_ texto: TextoDoLivro, capitulo: Int) -> String? {
        guard let c = listados(texto).first(where: { $0.indice == capitulo }) else { return nil }
        return "Cap. \(c.numero) · \(c.titulo)"
    }
}

enum FormatoDeTempo {
    /// "1:04" ou "1:10:00".
    static func relogio(_ segundos: Double) -> String {
        let t = Int(max(0, segundos.isFinite ? segundos : 0))
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t % 3600 / 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
    }

    static func segundos(palavras: Int, velocidade: Float) -> Double {
        Double(palavras) / (CortadorDeTrechos.palavrasPorMinuto * Double(velocidade)) * 60
    }
}

// MARK: - Barra de controles (OUV-001)

/// Barra em vidro: progresso do capítulo, velocidade, voltar e avançar 15, play, marcar,
/// e os botões de voz, capítulos e timer.
struct BarraDoPlayer: View {
    let tocador: Tocador
    let nomeDaVoz: String
    let marcar: () -> Void
    let abrir: (PainelDoPlayer) -> Void
    @State private var arrastando: Double?

    var body: some View {
        VStack(spacing: 12) {
            progresso
            HStack {
                Button { abrir(.velocidade) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "gauge.with.needle").font(.system(size: 14, weight: .semibold))
                        Text(Tocador.rotulo(tocador.velocidade)).font(Fonte.ui(15, .semibold)).monospacedDigit()
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
                botaoPlay
                Spacer()
                botaoDeSalto("goforward.15", "Avançar 15 segundos") { tocador.pular(15) }
                Spacer()
                Button(action: marcar) {
                    Image(systemName: "bookmark")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Cor.texto)
                        .frame(width: 52, height: 52)
                }
                .accessibilityLabel("Marcar este ponto")
            }
            .padding(.horizontal, 4)
            HStack(spacing: 6) {
                chip(nomeDaVoz, icone: "waveform", rotulo: "Voz: \(nomeDaVoz)") { abrir(.vozes) }
                chip("Capítulos", icone: "list.number", rotulo: "Capítulos e marcações") { abrir(.capitulos(.capitulos)) }
                TimelineView(.periodic(from: .now, by: 15)) { contexto in
                    let (texto, rotulo) = textoDoTimer(agora: contexto.date)
                    chip(texto, icone: "timer", rotulo: rotulo) { abrir(.timer) }
                }
            }
        }
        .padding(EdgeInsets(top: 16, leading: 12, bottom: 12, trailing: 12))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 32))
    }

    // MARK: Progresso do capítulo

    private var progresso: some View {
        let p = tocador.progressoDoCapitulo
        let fracao = arrastando ?? Double(p.ouvidas) / Double(p.total)
        let v = tocador.velocidade
        let ouvidoSeg = FormatoDeTempo.segundos(palavras: Int(Double(p.total) * fracao), velocidade: v)
        let faltam = "faltam " + TempoRestante.texto(palavras: p.total - Int(Double(p.total) * fracao), velocidade: v)
        return VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Cor.texto.opacity(0.12)).frame(height: 4)
                    Capsule().fill(Cor.progresso).frame(width: geo.size.width * fracao, height: 4)
                    Circle().fill(Cor.progresso).frame(width: 16, height: 16)
                        .position(x: geo.size.width * fracao, y: 12)
                }
                .frame(height: 24)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { arrastando = min(max($0.location.x / max(geo.size.width, 1), 0), 1) }
                    .onEnded { _ in
                        if let f = arrastando { tocador.irPara(fracaoDoCapitulo: f) }
                        arrastando = nil
                    })
            }
            .frame(height: 24)
            .accessibilityElement()
            .accessibilityLabel("Progresso do capítulo")
            .accessibilityValue("\(FormatoDeTempo.relogio(ouvidoSeg)), \(faltam)")
            .accessibilityAdjustableAction { direcao in
                tocador.pular(direcao == .increment ? 15 : -15)
            }

            HStack {
                if tocador.estado == .preparando {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "waveform").foregroundStyle(Cor.marca)
                        Text("Preparando a voz…")
                    }
                    .font(Fonte.ui(14, .semibold, relativoA: .subheadline))
                    .foregroundStyle(Paleta.laranja800)
                    Spacer()
                } else {
                    Text(FormatoDeTempo.relogio(ouvidoSeg))
                    Spacer()
                    Text(faltam)
                }
            }
            .font(Fonte.caption)
            .foregroundStyle(Cor.textoSecundario)
            .monospacedDigit()
        }
        .padding(.horizontal, 6)
    }

    private var botaoPlay: some View {
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
        .accessibilityLabel(tocador.estado == .preparando ? "Preparando a voz" : tocador.estado == .tocando ? "Pausar" : "Ouvir")
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

    private func chip(_ texto: String, icone: String, rotulo: String, _ acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            HStack(spacing: 6) {
                Image(systemName: icone).font(.system(size: 13, weight: .semibold))
                Text(texto).lineLimit(1)
            }
            .font(Fonte.ui(13, .semibold, relativoA: .caption))
            .foregroundStyle(Cor.texto)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(.white.opacity(0.55), in: Capsule())
        }
        .accessibilityLabel(rotulo)
    }

    /// Com o timer ligado, o botão mostra o tempo que falta, como "22 min" (OUV-013).
    private func textoDoTimer(agora: Date) -> (String, String) {
        switch tocador.timer {
        case nil: return ("Timer", "Timer de sono")
        case .fimDoCapitulo: return ("Fim do capítulo", "Timer de sono: fim do capítulo")
        case .minutos:
            let m = Int(((tocador.fimDoTimer ?? agora).timeIntervalSince(agora) / 60).rounded(.up))
            let t = TempoRestante.texto(minutos: max(m, 1))
            return (t, "Timer de sono: faltam \(t)")
        }
    }
}

// MARK: - Cabeçalho comum dos painéis

private struct CabecalhoDePainel<Conteudo: View>: View {
    let fechar: () -> Void
    @ViewBuilder let conteudo: Conteudo

    var body: some View {
        VStack(spacing: 14) {
            Capsule().fill(Cor.texto.opacity(0.2)).frame(width: 36, height: 5)
            HStack(spacing: 8) {
                conteudo
                Button(action: fechar) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Paleta.neutro700)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Fechar")
            }
            .padding(.trailing, -8)
        }
    }
}

// MARK: - Capítulos e marcações (OUV-007, OUV-008, OUV-009, OUV-017)

struct PainelDeCapitulos: View {
    enum Aba: Equatable { case capitulos, marcacoes }

    let tocador: Tocador
    let livro: LivroGuardado?
    let abaInicial: Aba
    let fechar: () -> Void
    let ir: (_ paragrafo: Int, _ local: Int) -> Void
    let excluirMarcacao: (Marcacao) -> Void
    @State private var aba: Aba = .capitulos

    var body: some View {
        VStack(spacing: 12) {
            CabecalhoDePainel(fechar: fechar) {
                HStack(spacing: 3) {
                    botaoDeAba("Capítulos", .capitulos)
                    botaoDeAba("Marcações", .marcacoes)
                }
                .padding(3)
                .frame(height: 44)
                .background(Cor.texto.opacity(0.07), in: Capsule())
            }
            switch aba {
            case .capitulos: capitulos
            case .marcacoes: marcacoes
            }
        }
        .padding(EdgeInsets(top: 8, leading: 18, bottom: 0, trailing: 18))
        .frame(maxHeight: .infinity, alignment: .top)
        .vidroDePainel()
        .onAppear { aba = abaInicial }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Capítulos e marcações")
    }

    private func botaoDeAba(_ titulo: String, _ valor: Aba) -> some View {
        let marcada = aba == valor
        return Button { withAnimation(.snappy) { aba = valor } } label: {
            Text(titulo)
                .font(Fonte.ui(15, marcada ? .semibold : .medium))
                .foregroundStyle(marcada ? Cor.texto : Paleta.neutro700)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    if marcada {
                        Capsule().fill(.white.opacity(0.85)).shadow(color: Cor.texto.opacity(0.1), radius: 4, y: 2)
                    }
                }
        }
        .accessibilityAddTraits(marcada ? .isSelected : [])
    }

    private var velocidade: Float { tocador.velocidade }

    // MARK: Capítulos

    private var capitulos: some View {
        let texto = tocador.texto
        let lista = NomesDeCapitulo.listados(texto)
        let atual = tocador.capituloAtual
        let faltaLivro = livro.map { TempoRestante.texto(palavras: $0.palavrasRestantes, velocidade: velocidade) } ?? ""
        return VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(tocador.livro.titulo ?? "")
                    .font(Fonte.marca(18, relativoA: .headline))
                    .tracking(-0.36)
                    .foregroundStyle(Cor.texto)
                    .lineLimit(1)
                Spacer()
                if lista.count > 1 {
                    Text("\(lista.count) capítulos · faltam \(faltaLivro)")
                        .font(Fonte.caption)
                        .foregroundStyle(Cor.textoSecundario)
                }
            }
            .padding(.horizontal, 2)
            ScrollViewReader { rolagem in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if lista.count <= 1 {
                            // OUV-017: livro sem capítulos é um capítulo só.
                            linhaAtual(titulo: "Livro inteiro", faltam: faltaLivro) { fechar() }
                        } else {
                            ForEach(lista, id: \.indice) { c in
                                if c.indice == atual {
                                    linhaAtual(titulo: c.titulo, faltam: faltamNoCapitulo) { fechar() }
                                        .id(c.indice)
                                } else {
                                    linha(numero: c.numero, titulo: c.titulo, minutos: minutos(doCapitulo: c.indice)) {
                                        ir(texto.capitulos[c.indice].primeiroParagrafo, 0)
                                    }
                                    .id(c.indice)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, -8)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                .onAppear { rolagem.scrollTo(atual, anchor: .center) }
            }
        }
    }

    private var faltamNoCapitulo: String {
        let p = tocador.progressoDoCapitulo
        return TempoRestante.texto(palavras: p.total - p.ouvidas, velocidade: velocidade)
    }

    private func minutos(doCapitulo i: Int) -> String {
        let t = tocador.texto
        let inicio = t.capitulos[i].primeiroParagrafo
        let fim = i + 1 < t.capitulos.count ? t.capitulos[i + 1].primeiroParagrafo : t.paragrafos.count
        let palavras = t.paragrafos[inicio..<fim].reduce(0) { $0 + TextoDoLivro.contarPalavras($1.texto) }
        return TempoRestante.texto(palavras: palavras, velocidade: velocidade)
    }

    private func linhaAtual(titulo: String, faltam: String, acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            HStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Cor.link)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(titulo).font(Fonte.ui(16, .semibold)).foregroundStyle(Cor.texto)
                    Text("Tocando agora").font(Fonte.ui(13, .medium, relativoA: .caption)).foregroundStyle(Cor.link)
                }
                Spacer()
                Text("faltam \(faltam)").font(Fonte.ui(13, .semibold, relativoA: .caption)).foregroundStyle(Cor.link)
            }
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 12)
            .frame(minHeight: 60)
            .background(Paleta.laranja100, in: RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityAddTraits(.isSelected)
    }

    private func linha(numero: Int, titulo: String, minutos: String, acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            HStack(spacing: 12) {
                Text("\(numero)").font(Fonte.ui(14)).foregroundStyle(Cor.textoSecundario).frame(width: 24)
                Text(titulo).font(Fonte.ui(16)).foregroundStyle(Cor.texto).frame(maxWidth: .infinity, alignment: .leading)
                Text(minutos).font(Fonte.caption).foregroundStyle(Cor.textoSecundario)
            }
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 12)
            .frame(minHeight: 60)
            .overlay(alignment: .bottom) { Rectangle().fill(Cor.fundoSutil).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Marcações

    @ViewBuilder private var marcacoes: some View {
        let lista = (livro?.marcacoes ?? []).sorted { $0.posicao < $1.posicao }
        if lista.isEmpty {
            // OUV-009: explicação curta de como marcar.
            VStack(spacing: 10) {
                Image(systemName: "bookmark")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Cor.link)
                    .frame(width: 64, height: 64)
                    .background(Paleta.laranja100, in: Circle())
                Text("Nenhuma marcação ainda")
                    .font(Fonte.ui(18, .semibold, relativoA: .headline))
                    .foregroundStyle(Cor.texto)
                Text("Enquanto ouve, toque no ícone de marcação para salvar o ponto e voltar a ele quando quiser.")
                    .font(Fonte.ui(15, relativoA: .callout))
                    .foregroundStyle(Paleta.neutro700)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 16)
            .padding(.top, 40)
            .frame(maxHeight: .infinity, alignment: .top)
        } else {
            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(tocador.livro.titulo ?? "")
                        .font(Fonte.marca(18, relativoA: .headline))
                        .foregroundStyle(Cor.texto)
                        .lineLimit(1)
                    Spacer()
                    Text(lista.count == 1 ? "1 marcação" : "\(lista.count) marcações")
                        .font(Fonte.caption)
                        .foregroundStyle(Cor.textoSecundario)
                }
                .padding(.horizontal, 2)
                List {
                    ForEach(lista) { m in
                        Button { ir(m.posicao.paragrafo, inicioDaFrase(m)) } label: { linhaDeMarcacao(m) }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                            .listRowSeparatorTint(Cor.fundoSutil)
                            // Excluir uma marcação é deslizar a linha (fluxo Ouvir um livro).
                            .swipeActions {
                                Button(role: .destructive) { excluirMarcacao(m) } label: {
                                    Label("Excluir", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func linhaDeMarcacao(_ m: Marcacao) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 15))
                .foregroundStyle(Cor.marca)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 4) {
                Text(NomesDeCapitulo.cabecalho(tocador.texto, capitulo: m.capitulo) ?? (tocador.livro.titulo ?? ""))
                    .font(Fonte.ui(13, .semibold, relativoA: .caption))
                    .foregroundStyle(Cor.textoSecundario)
                Text("“\(frase(m))”")
                    .font(Fonte.ui(15, relativoA: .callout))
                    .foregroundStyle(Cor.texto)
                    .lineLimit(3)
                Text(data(m.criadaEm))
                    .font(Fonte.caption)
                    .foregroundStyle(Cor.textoSecundario)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func inicioDaFrase(_ m: Marcacao) -> Int {
        guard m.posicao.paragrafo < tocador.texto.paragrafos.count else { return 0 }
        let p = tocador.texto.paragrafos[m.posicao.paragrafo]
        return p.frases.first { NSLocationInRange(m.posicao.deslocamento, $0) }?.location ?? m.posicao.deslocamento
    }

    /// A frase de onde a marcação começa.
    private func frase(_ m: Marcacao) -> String {
        guard m.posicao.paragrafo < tocador.texto.paragrafos.count else { return "" }
        let p = tocador.texto.paragrafos[m.posicao.paragrafo]
        let r = p.frases.first { NSLocationInRange(m.posicao.deslocamento, $0) } ?? NSRange(location: 0, length: (p.texto as NSString).length)
        let s = (p.texto as NSString).substring(with: r).trimmingCharacters(in: .whitespaces)
        return s.count > 110 ? String(s.prefix(105)).trimmingCharacters(in: .whitespaces) + "…" : s
    }

    /// "hoje" ou "8 de nov.", como no canvas.
    private func data(_ d: Date) -> String {
        if Calendar.current.isDateInToday(d) { return "hoje" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "d 'de' MMM"
        return f.string(from: d)
    }
}

// MARK: - Vozes (OUV-005)

struct PainelDeVozes: View {
    let tocador: Tocador
    let fechar: () -> Void
    let escolher: (String) -> Void
    @State private var vozes: [OpcaoDeVoz] = []
    @State private var amostra = Amostra()

    var body: some View {
        VStack(spacing: 14) {
            CabecalhoDePainel(fechar: fechar) {
                Text("Vozes")
                    .font(Fonte.ui(20, .bold, relativoA: .title3))
                    .foregroundStyle(Cor.texto)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(vozes) { voz in linha(voz) }
                }
            }
            .frame(maxHeight: 420)
            .fixedSize(horizontal: false, vertical: vozes.count < 6)
        }
        .padding(EdgeInsets(top: 8, leading: 18, bottom: 22, trailing: 18))
        .vidroDePainel()
        .onAppear { vozes = VozDoIPhone().vozes }
        .onDisappear { amostra.parar() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Vozes")
    }

    private func linha(_ voz: OpcaoDeVoz) -> some View {
        let marcada = voz.id == tocador.idDaVozEscolhida
        let tocando = amostra.tocando == voz.id
        return HStack(spacing: 12) {
            Button {
                if tocando { amostra.parar() } else {
                    if tocador.estado == .tocando { tocador.pausar() }
                    amostra.tocar(voz.id, texto: textoDaAmostra)
                }
            } label: {
                Image(systemName: tocando ? "pause.fill" : "play.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(tocando ? Cor.creme : Cor.texto)
                    .frame(width: 44, height: 44)
                    .background(tocando ? Cor.marca : Cor.fundoSutil, in: Circle())
            }
            .accessibilityLabel(tocando ? "Pausar a amostra de \(voz.nome)" : "Ouvir a amostra de \(voz.nome)")
            Button {
                amostra.parar()
                escolher(voz.id)
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(voz.nome).font(Fonte.ui(17, .semibold, relativoA: .headline)).foregroundStyle(Cor.texto)
                        if tocando {
                            Text("Tocando a amostra").font(Fonte.ui(14, relativoA: .subheadline)).foregroundStyle(Cor.textoSecundario)
                        }
                    }
                    Spacer()
                    if marcada {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Cor.creme)
                            .frame(width: 24, height: 24)
                            .background(Cor.marca, in: Circle())
                    } else {
                        Circle().strokeBorder(Paleta.neutro400, lineWidth: 2).frame(width: 24, height: 24)
                    }
                }
                .frame(minHeight: 60)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(marcada ? .isSelected : [])
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 68)
        .background(marcada ? Paleta.laranja100 : .clear, in: RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .bottom) { if !marcada { Rectangle().fill(Cor.fundoSutil).frame(height: 1) } }
    }

    /// A amostra lê a frase do livro onde a voz está.
    private var textoDaAmostra: String {
        let t = tocador.texto
        guard tocador.paragrafoAtual < t.paragrafos.count else { return "" }
        let p = t.paragrafos[tocador.paragrafoAtual]
        return p.frases.prefix(2).map { (p.texto as NSString).substring(with: $0) }.joined()
    }
}

// MARK: - Timer de sono (OUV-010)

struct PainelDeTimer: View {
    let tocador: Tocador
    let fechar: () -> Void

    private let opcoes: [(Tocador.Timer, String)] = [
        (.minutos(15), "15 minutos"), (.minutos(30), "30 minutos"), (.minutos(45), "45 minutos"),
        (.minutos(60), "1 hora"), (.fimDoCapitulo, "Fim do capítulo"),
    ]

    var body: some View {
        VStack(spacing: 14) {
            CabecalhoDePainel(fechar: fechar) {
                Text("Timer de sono")
                    .font(Fonte.ui(20, .bold, relativoA: .title3))
                    .foregroundStyle(Cor.texto)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(spacing: 0) {
                ForEach(opcoes, id: \.1) { opcao, titulo in
                    let marcada = tocador.timer == opcao
                    Button {
                        tocador.ligarTimer(opcao)
                        fechar()
                    } label: {
                        HStack {
                            Text(titulo).font(Fonte.ui(17, marcada ? .semibold : .regular, relativoA: .headline))
                            Spacer()
                            if marcada {
                                if case .minutos = opcao, let fim = tocador.fimDoTimer {
                                    Text("faltam " + TempoRestante.texto(minutos: Int((fim.timeIntervalSinceNow / 60).rounded(.up))))
                                        .font(Fonte.ui(13, .semibold, relativoA: .caption))
                                        .foregroundStyle(Cor.link)
                                }
                                Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Cor.marca)
                            }
                        }
                        .foregroundStyle(Cor.texto)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 56)
                        .background(marcada ? Paleta.laranja100 : .clear, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(alignment: .bottom) { if !marcada { Rectangle().fill(Cor.fundoSutil).frame(height: 1) } }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(marcada ? .isSelected : [])
                }
            }
            if tocador.timer != nil {
                Button {
                    tocador.desligarTimer()
                    fechar()
                } label: {
                    Text("Desligar timer")
                        .font(Fonte.headline)
                        .foregroundStyle(Cor.texto)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(.white.opacity(0.55), in: Capsule())
                        .overlay(Capsule().strokeBorder(Cor.texto.opacity(0.08)))
                }
                .padding(.top, 4)
            }
        }
        .padding(EdgeInsets(top: 8, leading: 18, bottom: 22, trailing: 18))
        .vidroDePainel()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Timer de sono")
    }
}
