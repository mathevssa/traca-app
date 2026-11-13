import SwiftUI
import UniformTypeIdentifiers

/// Biblioteca (IMP-001 a IMP-011): "Continuar ouvindo", a grade de capas, a busca,
/// os livros sendo importados, o menu e a exclusão, os avisos e o mini player.
struct TelaBiblioteca: View {
    @Environment(EstadoDoApp.self) private var app
    @State private var escolhendoArquivo = false
    @State private var busca = ""
    @FocusState private var buscando: Bool
    @State private var menuDoLivro: LivroGuardado?
    @State private var excluindo: LivroGuardado?

    private var biblioteca: Biblioteca { app.biblioteca }
    private var emBusca: Bool { buscando || !busca.isEmpty }
    private var velocidade: Float { app.tocador?.velocidade ?? Tocador.velocidadeGuardada }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                cabecalho
                if !vazia { campoDeBusca.padding(.top, 12) }
                if vazia {
                    BibliotecaVazia { escolhendoArquivo = true }
                } else if emBusca {
                    resultadosDaBusca
                } else {
                    if let livro = continuarOuvindo {
                        VStack(alignment: .leading, spacing: 10) {
                            Sobretitulo(texto: "Continuar ouvindo")
                            CardContinuarOuvindo(livro: livro, capa: biblioteca.capa(de: livro), velocidade: velocidade) {
                                app.abrir(livro)
                            }
                        }
                        .padding(.top, 14)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Sobretitulo(texto: "Seus livros · \(biblioteca.livros.count)")
                        grade(biblioteca.livros, comImportacoes: true)
                    }
                    .padding(.top, 22)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, app.tocador == nil ? 40 : 110)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Cor.fundo)
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .bottom) { rodape }
        .overlay { paineis }
        .fileImporter(isPresented: $escolhendoArquivo, allowedContentTypes: Formato.tiposAceitos, allowsMultipleSelection: true) { resultado in
            if case let .success(urls) = resultado { Task { await app.importar(urls) } }
        }
        .onDisappear { biblioteca.aviso = nil } // os avisos ficam até sair da biblioteca
        .animation(.snappy, value: emBusca)
        .animation(.snappy, value: biblioteca.aviso)
    }

    private var vazia: Bool { biblioteca.livros.isEmpty && biblioteca.importando.isEmpty }

    /// O último livro aberto e ainda não terminado.
    private var continuarOuvindo: LivroGuardado? {
        biblioteca.livros.first { $0.abertoEm != nil && !$0.terminado }
    }

    // MARK: Topo

    private var cabecalho: some View {
        HStack {
            Text("Biblioteca")
                .font(Fonte.ui(34, .bold, relativoA: .largeTitle))
                .tracking(-0.34)
                .foregroundStyle(Cor.texto)
            Spacer()
            HStack(spacing: 4) {
                Button { escolhendoArquivo = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Cor.textoSobreAcao)
                        .frame(width: 44, height: 44)
                        .background(Cor.acao, in: Circle())
                }
                .accessibilityLabel("Importar livro")
                // A tela Conta (CON-001) chega com o login, na fase de conta e assinatura.
                Image(systemName: "person")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Cor.texto)
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("Conta")
            }
            .padding(3)
            .glassEffect(.regular, in: Capsule())
            .padding(.trailing, -8)
        }
        .frame(height: 52)
        .padding(.top, 8)
    }

    private var campoDeBusca: some View {
        HStack(spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Cor.textoSecundario)
                TextField("Buscar por título ou autor", text: $busca)
                    .font(Fonte.ui(16))
                    .foregroundStyle(Cor.texto)
                    .focused($buscando)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Buscar na biblioteca")
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(Cor.texto.opacity(0.06), in: Capsule())
            .overlay { if buscando { Capsule().strokeBorder(Cor.marca, lineWidth: 2) } }

            if emBusca {
                Button("Cancelar") {
                    busca = ""
                    buscando = false
                }
                .font(Fonte.ui(16, .semibold))
                .foregroundStyle(Cor.link)
                .padding(.leading, 10)
                .frame(height: 44)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    // MARK: Busca (IMP-008 e IMP-009)

    /// Busca por título e autor, sem diferenciar maiúscula nem acento, filtrando enquanto o leitor digita.
    private var encontrados: [LivroGuardado] {
        let termo = busca.trimmingCharacters(in: .whitespaces)
        guard !termo.isEmpty else { return biblioteca.livros }
        return biblioteca.livros.filter { livro in
            [livro.titulo, livro.autor ?? ""].contains {
                $0.range(of: termo, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }

    @ViewBuilder private var resultadosDaBusca: some View {
        let lista = encontrados
        if lista.isEmpty {
            VStack(spacing: 8) {
                Text("Nenhum livro encontrado")
                    .font(Fonte.ui(22, .bold, relativoA: .title2))
                    .foregroundStyle(Cor.texto)
                Text("Confira o nome ou importe o livro.")
                    .font(Fonte.ui(16))
                    .foregroundStyle(Paleta.neutro700)
                Button { escolhendoArquivo = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.badge.plus").font(.system(size: 18, weight: .semibold))
                        Text("Importar livro")
                    }
                    .font(Fonte.headline)
                    .foregroundStyle(Cor.texto)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .glassEffect(.regular, in: Capsule())
                }
                .padding(.top, 18)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 72)
            .padding(.horizontal, 8)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Sobretitulo(texto: lista.count == 1 ? "1 livro" : "\(lista.count) livros")
                grade(lista, comImportacoes: false)
            }
            .padding(.top, 18)
        }
    }

    // MARK: Grade

    private func grade(_ livros: [LivroGuardado], comImportacoes: Bool) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], alignment: .leading, spacing: 18) {
            if comImportacoes {
                ForEach(biblioteca.importando) { CardImportando(importacao: $0) }
            }
            ForEach(livros) { livro in
                CardDoLivro(livro: livro, capa: biblioteca.capa(de: livro), velocidade: velocidade)
                    .contentShape(Rectangle())
                    .onTapGesture { app.abrir(livro) }
                    .onLongPressGesture { withAnimation(.spring(duration: 0.35)) { menuDoLivro = livro } }
                    .accessibilityAction(named: "Opções do livro \(livro.titulo)") { menuDoLivro = livro }
            }
        }
    }

    // MARK: Rodapé: aviso e mini player

    private var rodape: some View {
        VStack(spacing: 12) {
            if let aviso = biblioteca.aviso {
                AvisoFlutuante(texto: aviso.texto, icone: aviso == .repetido ? "books.vertical" : "exclamationmark.circle") {
                    biblioteca.aviso = nil
                }
                .padding(.horizontal, 4)
            }
            if let tocador = app.tocador, let livro = app.livroDoTocador {
                MiniPlayer(tocador: tocador, livro: livro, capa: biblioteca.capa(de: livro)) {
                    app.caminho = [.player]
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // MARK: Menu do livro (IMP-005) e Excluir livro (IMP-006)

    @ViewBuilder private var paineis: some View {
        if let livro = menuDoLivro {
            ZStack(alignment: .bottom) {
                Escurecimento { fecharMenu() }
                MenuDoLivro(livro: livro, capa: biblioteca.capa(de: livro), velocidade: velocidade, excluir: {
                    fecharMenu()
                    withAnimation(.spring(duration: 0.3)) { excluindo = livro }
                }, cancelar: fecharMenu)
                .padding(8)
                .transition(.move(edge: .bottom))
            }
        }
        if let livro = excluindo {
            ZStack {
                Escurecimento { excluindo = nil }
                DialogoExcluirLivro(livro: livro, capa: biblioteca.capa(de: livro), excluir: {
                    withAnimation { excluindo = nil }
                    app.excluir(livro)
                }, cancelar: { withAnimation { excluindo = nil } })
                .padding(.horizontal, 40)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
    }

    private func fecharMenu() {
        withAnimation(.spring(duration: 0.3)) { menuDoLivro = nil }
    }
}

// MARK: - Peças da biblioteca

/// O que aparece embaixo de cada capa: "Novo · 6 h 40 min", "faltam 4 h 12 min" ou "Terminado".
private func situacao(_ livro: LivroGuardado, velocidade: Float) -> String {
    if livro.terminado { return "Terminado" }
    let tempo = TempoRestante.texto(palavras: livro.palavrasRestantes, velocidade: velocidade)
    return livro.abertoEm == nil ? "Novo · \(tempo)" : "faltam \(tempo)"
}

private func progresso(_ livro: LivroGuardado) -> Double {
    guard livro.totalDePalavras > 0 else { return 0 }
    return 1 - Double(livro.palavrasRestantes) / Double(livro.totalDePalavras)
}

struct CardDoLivro: View {
    let livro: LivroGuardado
    let capa: UIImage?
    let velocidade: Float

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CapaDoLivro(titulo: livro.titulo, imagem: capa)
                .frame(maxWidth: .infinity)
                .frame(height: 196)
            if livro.abertoEm != nil && !livro.terminado {
                BarraDeProgresso(fracao: progresso(livro))
            } else {
                Color.clear.frame(height: 3)
            }
            Text(livro.titulo)
                .font(Fonte.ui(15, .semibold))
                .foregroundStyle(Cor.texto)
                .lineLimit(1)
            if let autor = livro.autor {
                Text(autor)
                    .font(Fonte.caption)
                    .foregroundStyle(Cor.textoSecundario)
                    .lineLimit(1)
            }
            Text(situacao(livro, velocidade: velocidade))
                .font(Fonte.ui(13, relativoA: .caption))
                .foregroundStyle(Paleta.neutro700)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Card de um arquivo sendo importado (IMP-003).
struct CardImportando: View {
    let importacao: Importacao
    @State private var andando = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(spacing: 8) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(Cor.link)
                Text("Importando…")
                    .font(Fonte.ui(13, relativoA: .caption))
                    .foregroundStyle(Paleta.neutro700)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 196)
            .background(Cor.fundoElevado, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Paleta.neutro400, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Paleta.neutro300)
                    Capsule().fill(Paleta.neutro400)
                        .frame(width: geo.size.width * 0.45)
                        .offset(x: andando ? geo.size.width * 0.55 : 0)
                }
                .clipShape(Capsule())
            }
            .frame(height: 3)
            Text(importacao.nomeDoArquivo)
                .font(Fonte.ui(15, .semibold))
                .foregroundStyle(Cor.texto)
                .lineLimit(1)
            Sobretitulo(texto: "Importando", cor: Cor.link)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { andando = true }
        }
        .accessibilityElement(children: .combine)
    }
}

/// "Continuar ouvindo" com o último livro aberto (IMP-002).
struct CardContinuarOuvindo: View {
    let livro: LivroGuardado
    let capa: UIImage?
    let velocidade: Float
    let ouvir: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            CapaDoLivro(titulo: livro.titulo, imagem: capa, raio: 8, tamanhoDoTitulo: 10)
                .frame(width: 72, height: 104)
            VStack(alignment: .leading, spacing: 4) {
                Text(livro.titulo)
                    .font(Fonte.marca(20, relativoA: .title3))
                    .tracking(-0.4)
                    .foregroundStyle(Cor.texto)
                    .lineLimit(2)
                if let autor = livro.autor {
                    Text(autor).font(Fonte.ui(14, relativoA: .subheadline)).foregroundStyle(Cor.textoSecundario)
                }
                Text(detalhe)
                    .font(Fonte.ui(13, relativoA: .caption))
                    .foregroundStyle(Paleta.neutro700)
                BarraDeProgresso(fracao: progresso(livro), altura: 4)
                    .padding(.top, 6)
            }
            Button(action: ouvir) {
                Image(systemName: "play.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Cor.creme)
                    .frame(width: 48, height: 48)
                    .background(Cor.play, in: Circle())
            }
            .accessibilityLabel("Ouvir \(livro.titulo)")
        }
        .padding(14)
        .background(Cor.fundoElevado, in: RoundedRectangle(cornerRadius: 20))
        .contentShape(Rectangle())
        .onTapGesture(perform: ouvir)
    }

    private var detalhe: String {
        let faltam = "faltam " + TempoRestante.texto(palavras: livro.palavrasRestantes, velocidade: velocidade)
        return livro.capituloAtual > 0 ? "Cap. \(livro.capituloAtual) · \(faltam)" : faltam
    }
}

/// Mini player em vidro na biblioteca (IMP-002).
struct MiniPlayer: View {
    let tocador: Tocador
    let livro: LivroGuardado
    let capa: UIImage?
    let abrir: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            CapaDoLivro(titulo: livro.titulo, imagem: capa, raio: 8, tamanhoDoTitulo: 5)
                .frame(width: 40, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(livro.titulo)
                    .font(Fonte.marca(15, relativoA: .subheadline))
                    .tracking(-0.3)
                    .foregroundStyle(Cor.texto)
                    .lineLimit(1)
                Text("faltam " + TempoRestante.texto(palavras: livro.palavrasRestantes, velocidade: tocador.velocidade))
                    .font(Fonte.ui(12, relativoA: .caption2))
                    .foregroundStyle(Cor.textoSecundario)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { tocador.pular(-15) } label: {
                Image(systemName: "gobackward.15")
                    .font(.system(size: 22))
                    .foregroundStyle(Cor.texto)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Voltar 15 segundos")
            Button { tocador.alternar() } label: {
                Group {
                    if tocador.estado == .preparando {
                        ProgressView().tint(Cor.creme)
                    } else {
                        Image(systemName: tocador.estado == .tocando ? "pause.fill" : "play.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Cor.creme)
                    }
                }
                .frame(width: 44, height: 44)
                .background(Cor.play, in: Circle())
            }
            .accessibilityLabel(tocador.estado == .tocando ? "Pausar" : "Ouvir")
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .frame(height: 64)
        .overlay(alignment: .bottom) {
            BarraDeProgresso(fracao: progresso(livro), altura: 2)
                .padding(.horizontal, 28)
        }
        .glassEffect(.regular, in: Capsule())
        .contentShape(Capsule())
        .onTapGesture(perform: abrir)
    }
}

/// IMP-001: o convite para importar o primeiro livro e os formatos aceitos.
struct BibliotecaVazia: View {
    let importar: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(Cor.fundoSutil)
                .frame(width: 132, height: 132)
                .overlay {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(Cor.marca)
                        .frame(width: 76, height: 76)
                        .overlay { DesenhoIcone().stroke(Cor.creme, style: StrokeStyle(lineWidth: 6.5, lineCap: .round)) }
                }
                .accessibilityHidden(true)
            Text("Traga seu primeiro livro")
                .font(Fonte.ui(26, .bold, relativoA: .title))
                .foregroundStyle(Cor.texto)
                .padding(.top, 28)
            Text("Importe um ebook que você já tem e ouça na hora, com o texto acompanhando a voz.")
                .font(Fonte.ui(16))
                .foregroundStyle(Paleta.neutro700)
                .padding(.top, 10)
            BotaoPrincipal(titulo: "Importar livro", icone: "doc.badge.plus", acao: importar)
                .padding(.top, 26)
            VStack(spacing: 10) {
                Sobretitulo(texto: "Formatos aceitos")
                FlowDeChips(itens: Formato.allCases.map(\.rawValue))
                Text("Sem proteção contra cópia (DRM)")
                    .font(Fonte.ui(13, relativoA: .caption))
                    .foregroundStyle(Cor.textoSecundario)
            }
            .padding(.top, 22)

            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Cor.link)
                    .frame(width: 40, height: 40)
                    .background(Paleta.laranja100, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Também dá pelo Compartilhar")
                        .font(Fonte.ui(15, .semibold))
                        .foregroundStyle(Cor.texto)
                    Text("No app Arquivos, no Mail ou no navegador, toque em Compartilhar no livro e escolha o Traça.")
                        .font(Fonte.ui(14, relativoA: .subheadline))
                        .foregroundStyle(Paleta.neutro700)
                }
                .multilineTextAlignment(.leading)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Cor.fundoElevado, in: RoundedRectangle(cornerRadius: 20))
            .padding(.top, 48)
        }
        .multilineTextAlignment(.center)
        .padding(.top, 56)
        .padding(.horizontal, 8)
    }
}

/// Chips que quebram linha (formatos aceitos).
struct FlowDeChips: View {
    let itens: [String]
    var body: some View {
        FlowLayout(espaco: 6) {
            ForEach(itens, id: \.self) { item in
                Text(item)
                    .font(Fonte.ui(13, .semibold, relativoA: .caption))
                    .foregroundStyle(Paleta.neutro700)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(Cor.fundoSutil, in: Capsule())
            }
        }
    }
}

/// Arranjo simples que põe os itens lado a lado e quebra linha quando não cabe, centralizado.
struct FlowLayout: Layout {
    var espaco: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let linhas = organizar(largura: proposal.width ?? .infinity, subviews: subviews)
        let altura = linhas.map(\.altura).reduce(0, +) + espaco * CGFloat(max(0, linhas.count - 1))
        return CGSize(width: proposal.width ?? linhas.map(\.largura).max() ?? 0, height: altura)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for linha in organizar(largura: bounds.width, subviews: subviews) {
            var x = bounds.minX + (bounds.width - linha.largura) / 2
            for i in linha.itens {
                let t = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(t))
                x += t.width + espaco
            }
            y += linha.altura + espaco
        }
    }

    private func organizar(largura: CGFloat, subviews: Subviews) -> [(itens: [Int], largura: CGFloat, altura: CGFloat)] {
        var linhas: [(itens: [Int], largura: CGFloat, altura: CGFloat)] = []
        var atual: (itens: [Int], largura: CGFloat, altura: CGFloat) = ([], 0, 0)
        for (i, s) in subviews.enumerated() {
            let t = s.sizeThatFits(.unspecified)
            let nova = atual.itens.isEmpty ? t.width : atual.largura + espaco + t.width
            if nova > largura, !atual.itens.isEmpty {
                linhas.append(atual)
                atual = ([i], t.width, t.height)
            } else {
                atual = (atual.itens + [i], nova, max(atual.altura, t.height))
            }
        }
        if !atual.itens.isEmpty { linhas.append(atual) }
        return linhas
    }
}

/// IMP-005: menu do livro, com Excluir livro.
struct MenuDoLivro: View {
    let livro: LivroGuardado
    let capa: UIImage?
    let velocidade: Float
    let excluir: () -> Void
    let cancelar: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Capsule().fill(Paleta.neutro300).frame(width: 36, height: 5)
            HStack(spacing: 14) {
                CapaDoLivro(titulo: livro.titulo, imagem: capa, raio: 6, tamanhoDoTitulo: 8)
                    .frame(width: 56, height: 80)
                VStack(alignment: .leading, spacing: 3) {
                    Text(livro.titulo)
                        .font(Fonte.marca(20, relativoA: .title3))
                        .tracking(-0.4)
                        .foregroundStyle(Cor.texto)
                    if let autor = livro.autor {
                        Text(autor).font(Fonte.ui(14, relativoA: .subheadline)).foregroundStyle(Cor.textoSecundario)
                    }
                    Text(situacao(livro, velocidade: velocidade))
                        .font(Fonte.ui(13, relativoA: .caption))
                        .foregroundStyle(Paleta.neutro700)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            Button(action: excluir) {
                HStack(spacing: 12) {
                    Image(systemName: "trash").font(.system(size: 18, weight: .semibold))
                    Text("Excluir livro")
                    Spacer()
                }
                .font(Fonte.ui(17, .semibold, relativoA: .headline))
                .foregroundStyle(Cor.erro)
                .padding(.horizontal, 16)
                .frame(minHeight: 56)
                .background(.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Cor.texto.opacity(0.06)))
            }
            Button(action: cancelar) {
                Text("Cancelar")
                    .font(Fonte.ui(17, .semibold, relativoA: .headline))
                    .foregroundStyle(Cor.texto)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(.white.opacity(0.55), in: Capsule())
                    .overlay(Capsule().strokeBorder(Cor.texto.opacity(0.08)))
            }
        }
        .padding(EdgeInsets(top: 10, leading: 18, bottom: 18, trailing: 18))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 34))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Opções do livro \(livro.titulo)")
    }
}

/// IMP-006: confirmação antes de excluir. Avisa que as marcações também são apagadas.
struct DialogoExcluirLivro: View {
    let livro: LivroGuardado
    let capa: UIImage?
    let excluir: () -> Void
    let cancelar: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            CapaDoLivro(titulo: livro.titulo, imagem: capa, raio: 6, tamanhoDoTitulo: 7)
                .frame(width: 48, height: 68)
            Text([livro.titulo, livro.autor].compactMap { $0 }.joined(separator: " · "))
                .font(Fonte.caption)
                .foregroundStyle(Cor.textoSecundario)
                .padding(.bottom, 6)
            Text("Excluir este livro?")
                .font(Fonte.ui(18, .semibold, relativoA: .headline))
                .foregroundStyle(Cor.texto)
            Text("As marcações dele também serão apagadas. Não dá para desfazer.")
                .font(Fonte.ui(15, relativoA: .callout))
                .foregroundStyle(Paleta.neutro700)
            VStack(spacing: 8) {
                Button(action: excluir) {
                    Text("Excluir")
                        .font(Fonte.ui(16, .semibold))
                        .foregroundStyle(Cor.creme)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Cor.erro, in: Capsule())
                }
                Button(action: cancelar) {
                    Text("Cancelar")
                        .font(Fonte.ui(16, .semibold))
                        .foregroundStyle(Cor.texto)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(.white.opacity(0.55), in: Capsule())
                        .overlay(Capsule().strokeBorder(Cor.texto.opacity(0.08)))
                }
            }
            .padding(.top, 10)
        }
        .multilineTextAlignment(.center)
        .padding(EdgeInsets(top: 22, leading: 18, bottom: 16, trailing: 18))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 34))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

extension Formato {
    /// Tipos de arquivo que o seletor do iOS deixa escolher.
    static var tiposAceitos: [UTType] {
        [.epub, .pdf, .plainText, .rtf]
            + ["mobi", "azw3", "azw", "prc", "fb2"].compactMap { UTType(filenameExtension: $0) }
    }
}
