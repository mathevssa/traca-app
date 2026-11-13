import SwiftUI

/// Boas-vindas (CMC-001), com a importação do primeiro livro (CMC-002) e o erro (CMC-003).
/// "Ouvir o livro de amostra" entra com a narração da amostra, e "Já tenho conta" com o login.
struct TelaBoasVindas: View {
    @Environment(EstadoDoApp.self) private var app
    @State private var escolhendoArquivo = false
    @State private var importando = false
    @State private var erro: ErroDeLeitura?

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Logotipo()
            VStack(alignment: .leading, spacing: 12) {
                Text("Seus livros, lidos em voz alta.")
                    .font(Fonte.marca(34, relativoA: .largeTitle))
                    .tracking(-0.68)
                    .foregroundStyle(Cor.texto)
                Text("Escolha um ebook que você já tem e ouça com o texto acompanhando a voz.")
                    .font(Fonte.body)
                    .foregroundStyle(Paleta.neutro700)
            }
            ouvindoAgora
            Spacer(minLength: 0)
            rodape
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Cor.fundo)
        .toolbar(.hidden, for: .navigationBar)
        .fileImporter(isPresented: $escolhendoArquivo, allowedContentTypes: Formato.tiposAceitos) { resultado in
            if case let .success(url) = resultado { importar(url) }
        }
    }

    /// Exemplo do texto acompanhando a voz, como no canvas.
    private var ouvindoAgora: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Cor.marca)
                Sobretitulo(texto: "Ouvindo agora")
            }
            Text(exemplo)
                .font(Fonte.ui(17))
                .lineSpacing(6)
        }
        .padding(EdgeInsets(top: 18, leading: 18, bottom: 16, trailing: 18))
        .background(Cor.fundoElevado, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Cor.fundoSutil))
        .accessibilityHidden(true)
    }

    private var exemplo: AttributedString {
        var lido = AttributedString("Uma noite destas, vindo da cidade para o Engenho Novo, encontrei no trem da Central um rapaz aqui do bairro, ")
        lido.foregroundColor = Cor.leituraFeita
        return lido + fraseDestacada
    }

    private var fraseDestacada: AttributedString {
        var a = AttributedString("que eu conheço de vista e de chapéu.")
        a.backgroundColor = Cor.leituraFrase
        a.foregroundColor = Cor.texto
        if let r = a.range(of: "vista") {
            a[r].foregroundColor = Cor.leituraPalavra
            a[r].font = Fonte.ui(17, .bold)
        }
        return a
    }

    @ViewBuilder private var rodape: some View {
        VStack(spacing: 12) {
            if let erro {
                // CMC-003: a mensagem do motivo, acima do botão.
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x8C1D18))
                    Text(AvisoDaBiblioteca.erro(erro).texto)
                        .font(Fonte.ui(15, relativoA: .callout))
                        .foregroundStyle(Color(hex: 0x8C1D18))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
                .background(Color(hex: 0xFCE9E7), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color(hex: 0xF2C6C2)))
                .accessibilityAddTraits(.isStaticText)
            } else {
                Text("5 minutos grátis para ouvir, sem cadastro.")
                    .font(Fonte.ui(14, relativoA: .subheadline))
                    .foregroundStyle(Paleta.neutro700)
                    .frame(maxWidth: .infinity)
            }
            if importando {
                // CMC-002: o botão vira a barra de progresso, com o texto fixo "Importando arquivo…".
                VStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(Cor.marca)
                    Text("Importando arquivo…")
                        .font(Fonte.headline)
                        .foregroundStyle(Cor.texto)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Cor.fundoSutil, in: Capsule())
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Importando o livro")
            } else {
                BotaoPrincipal(titulo: erro == nil ? "Escolher um livro do iPhone" : "Escolher outro livro",
                               icone: "doc.badge.plus") { escolhendoArquivo = true }
            }
        }
    }

    private func importar(_ url: URL) {
        erro = nil
        importando = true
        Task {
            await app.importar([url])
            importando = false
            if case let .erro(e) = app.biblioteca.aviso {
                erro = e
                app.biblioteca.aviso = nil
            }
        }
    }
}
