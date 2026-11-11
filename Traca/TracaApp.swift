import SwiftUI

@main
struct TracaApp: App {
    var body: some Scene {
        WindowGroup {
            TelaDeTeste()
                // O MVP é sempre claro (marca.md, "Linguagem visual do app").
                .preferredColorScheme(.light)
        }
    }
}
