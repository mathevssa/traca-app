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
                    }
                }
            }
            .environment(app)
            // Livro vindo do "Compartilhar" de outro app (Arquivos, Mail, navegador).
            .onOpenURL { url in Task { await app.importar([url]) } }
            // O MVP é sempre claro (marca.md, "Linguagem visual do app").
            .preferredColorScheme(.light)
            .tint(Cor.acao)
        }
    }
}
