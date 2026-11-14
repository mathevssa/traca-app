import SwiftUI

@main
struct TracaApp: App {
    @State private var app = EstadoDoApp()

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $app.caminho) {
                // Antes do primeiro livro, o app abre em Boas-vindas; depois, na Biblioteca.
                Group {
                    if app.biblioteca.jaImportou { TelaBiblioteca() } else { TelaBoasVindas() }
                }
                .navigationDestination(for: Rota.self) { rota in
                    switch rota {
                    case .escolherVoz(let id): TelaEscolherVoz(livroID: id)
                    case .player: if let tocador = app.tocador { TelaDoPlayer(tocador: tocador) }
                    case .conta: TelaConta()
                    }
                }
            }
            .overlay {
                // Entrar com a Apple ou o Google (CMC-007 e CMC-010), por cima de qualquer tela.
                if let painel = app.painelDeEntrar {
                    ZStack(alignment: .bottom) {
                        Escurecimento { app.painelDeEntrar = nil }
                        PainelEntrar(tipo: painel, entrar: { app.entrar(com: $0) }, agoraNao: { app.painelDeEntrar = nil })
                            .padding(8)
                            .transition(.move(edge: .bottom))
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let aviso = app.avisoGeral {
                    // ASS-006 e ASS-007: o aviso aparece onde o leitor estava.
                    AvisoFlutuante(texto: aviso.texto, icone: "checkmark.circle") { app.avisoGeral = nil }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 110)
                }
            }
            .animation(.spring(duration: 0.35), value: app.painelDeEntrar)
            .animation(.snappy, value: app.avisoGeral)
            .fullScreenCover(isPresented: $app.mostrandoAssinar) { TelaAssinar().environment(app) }
            .onChange(of: app.loja.situacao) { _, _ in app.assinaturaMudou() }
            .environment(app)
            // Livro vindo do "Compartilhar" de outro app (Arquivos, Mail, navegador).
            .onOpenURL { url in Task { await app.importar([url]) } }
            // O MVP é sempre claro (marca.md, "Linguagem visual do app").
            .preferredColorScheme(.light)
            .tint(Cor.acao)
        }
    }
}
