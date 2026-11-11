import SwiftUI
import UniformTypeIdentifiers

/// Tela provisória da Fase 0: importa um arquivo e abre o player.
/// A biblioteca de verdade (IMP-001 a IMP-011) vem na Fase 2.
struct TelaDeTeste: View {
    @State private var livros: [URL] = []
    @State private var escolhendo = false
    @State private var abrindo = false
    @State private var erro: String?
    @State private var tocador: Tocador?
    @State private var mostrandoPlayer = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Logotipo()
                    Text("Seus livros, lidos em voz alta.")
                        .font(Fonte.marca(34))
                        .tracking(-0.68)
                        .foregroundStyle(Cor.texto)

                    VStack(spacing: 0) {
                        ForEach(livros, id: \.self) { url in
                            Button { abrir(url) } label: {
                                HStack {
                                    Text(url.deletingPathExtension().lastPathComponent)
                                        .font(Fonte.headline)
                                        .foregroundStyle(Cor.texto)
                                    Spacer()
                                    Text(url.pathExtension.uppercased())
                                        .font(Fonte.caption)
                                        .foregroundStyle(Cor.textoSecundario)
                                }
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider().overlay(Cor.borda)
                        }
                    }

                    if let erro {
                        Text(erro)
                            .font(Fonte.callout)
                            .foregroundStyle(Cor.erro)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .safeAreaInset(edge: .bottom) {
                Button { escolhendo = true } label: {
                    HStack(spacing: 10) {
                        if abrindo { ProgressView().tint(Cor.textoSobreAcao) }
                        Text("Escolher um livro do iPhone")
                    }
                    .font(Fonte.headline)
                    .foregroundStyle(Cor.textoSobreAcao)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Cor.acao, in: Capsule())
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
                .disabled(abrindo)
            }
            .background(Cor.fundo)
            .navigationDestination(isPresented: $mostrandoPlayer) {
                if let tocador { TelaDoPlayer(tocador: tocador) }
            }
        }
        .fileImporter(isPresented: $escolhendo, allowedContentTypes: Self.tipos, allowsMultipleSelection: false) { resultado in
            if case let .success(urls) = resultado, let url = urls.first { importar(url) }
        }
        .onOpenURL { importar($0) }
        .onAppear(perform: carregarLista)
    }

    static let tipos: [UTType] = [.epub, .pdf, .plainText, .rtf]
        + ["mobi", "azw3", "azw", "prc", "fb2"].compactMap { UTType(filenameExtension: $0) }

    static var pasta: URL {
        let p = URL.documentsDirectory.appendingPathComponent("Livros", isDirectory: true)
        try? FileManager.default.createDirectory(at: p, withIntermediateDirectories: true)
        return p
    }

    private func carregarLista() {
        livros = ((try? FileManager.default.contentsOfDirectory(at: Self.pasta, includingPropertiesForKeys: nil)) ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Copia o arquivo escolhido para dentro do app e abre.
    private func importar(_ origem: URL) {
        let acesso = origem.startAccessingSecurityScopedResource()
        defer { if acesso { origem.stopAccessingSecurityScopedResource() } }
        let destino = Self.pasta.appendingPathComponent(origem.lastPathComponent)
        try? FileManager.default.removeItem(at: destino)
        do { try FileManager.default.copyItem(at: origem, to: destino) } catch {
            erro = "Não conseguimos abrir este arquivo. Ele pode estar danificado. Tente baixar de novo."
            return
        }
        carregarLista()
        abrir(destino)
    }

    private func abrir(_ url: URL) {
        erro = nil
        abrindo = true
        Task {
            let resultado = await Task.detached(priority: .userInitiated) { Result { try LeitorDeLivros.ler(url) } }.value
            abrindo = false
            switch resultado {
            case .success(let livro):
                tocador?.encerrar()
                let voz = VozDoIPhone()
                guard let id = voz.vozes.first?.id else { return }
                tocador = Tocador(livro: livro, voz: voz, idDaVoz: id)
                mostrandoPlayer = true
            case .failure(let e):
                erro = Self.mensagem(e as? ErroDeLeitura ?? .corrompido)
            }
        }
    }

    /// Mensagens de fluxos/importar-e-excluir-livros.md.
    static func mensagem(_ e: ErroDeLeitura) -> String {
        switch e {
        case .drm: "Este livro tem proteção contra cópia (DRM) e não abre fora da loja onde foi comprado. Tente um arquivo sem proteção."
        case .corrompido: "Não conseguimos abrir este arquivo. Ele pode estar danificado. Tente baixar de novo."
        case .formatoNaoAceito: "O Traça ainda não abre esse tipo de arquivo. Ele abre EPUB, PDF, MOBI, AZW3, FB2, TXT e RTF."
        }
    }
}

#Preview { TelaDeTeste() }
