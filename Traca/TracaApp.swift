import SwiftUI

@main
struct TracaApp: App {
    var body: some Scene {
        WindowGroup {
            TelaInicial()
                // O MVP é sempre claro (marca.md, "Linguagem visual do app").
                .preferredColorScheme(.light)
        }
    }
}
