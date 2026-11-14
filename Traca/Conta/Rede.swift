import Network
import Observation

/// Diz se o iPhone está com internet, para os avisos "Você está sem internet".
@Observable
final class Rede {
    private(set) var conectada = true
    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] caminho in
            let ok = caminho.status == .satisfied
            Task { @MainActor in self?.conectada = ok }
        }
        monitor.start(queue: DispatchQueue(label: "app.traca.rede"))
    }
}
