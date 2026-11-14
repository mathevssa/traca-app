import Foundation
import Observation

/// A identidade do leitor no Traça (objeto Conta): criada no primeiro login com a Apple ou o Google.
nonisolated struct Conta: Codable, Hashable, Identifiable {
    enum Provedor: String, Codable { case apple = "Apple", google = "Google" }

    let id: UUID
    let provedor: Provedor
    /// O identificador que a Apple ou o Google devolve. É o que reconhece o leitor no próximo login.
    let idDoProvedor: String
    let email: String
    var nome: String?
    /// Começa desligado (objeto Conta).
    var aceitaEmails = false
    let criadaEm: Date
}

/// Login e saída da conta.
///
/// PROVISÓRIO: o login de verdade com a Apple e o Google depende da conta paga de
/// desenvolvedor da Apple e do servidor (fase de conta e assinatura). Até lá, "Entrar"
/// cria uma conta de teste guardada só neste aparelho. Cada provedor tem sempre a mesma
/// conta de teste, para sair e entrar de novo funcionar como no app de verdade.
@Observable
final class Contas {
    private(set) var atual: Conta?
    private let arquivo = URL.applicationSupportDirectory.appendingPathComponent("conta.json")
    private let arquivoDasContas = URL.applicationSupportDirectory.appendingPathComponent("contas-de-teste.json")

    init() {
        atual = (try? Data(contentsOf: arquivo)).flatMap { try? JSONDecoder().decode(Conta.self, from: $0) }
    }

    /// Pasta onde ficam os livros de uma conta. Excluir a conta apaga essa pasta.
    static func pasta(de conta: Conta) -> URL {
        URL.applicationSupportDirectory.appendingPathComponent("Contas/\(conta.id.uuidString)", isDirectory: true)
    }

    /// Entra com a Apple ou o Google. PROVISÓRIO: sem a tela do provedor, entra direto na conta de teste.
    func entrar(com provedor: Conta.Provedor) -> Conta {
        var conhecidas = contasConhecidas()
        let conta = conhecidas[provedor.rawValue] ?? Conta(
            id: UUID(), provedor: provedor, idDoProvedor: "teste-\(provedor.rawValue.lowercased())",
            email: "leitor@exemplo.com", nome: nil, criadaEm: .now)
        conhecidas[provedor.rawValue] = conta
        if let d = try? JSONEncoder().encode(conhecidas) { try? d.write(to: arquivoDasContas) }
        definir(conta)
        return conta
    }

    func atualizar(_ mudar: (inout Conta) -> Void) {
        guard var c = atual else { return }
        mudar(&c)
        definir(c)
        var conhecidas = contasConhecidas()
        conhecidas[c.provedor.rawValue] = c
        if let d = try? JSONEncoder().encode(conhecidas) { try? d.write(to: arquivoDasContas) }
    }

    /// Sair não apaga nada da conta: ao entrar de novo, a biblioteca volta.
    func sair() {
        definir(nil)
    }

    /// Apaga os dados da conta. PROVISÓRIO: sem servidor, apaga só o que está neste aparelho.
    func excluir() {
        guard let c = atual else { return }
        try? FileManager.default.removeItem(at: Self.pasta(de: c))
        var conhecidas = contasConhecidas()
        conhecidas[c.provedor.rawValue] = nil
        if let d = try? JSONEncoder().encode(conhecidas) { try? d.write(to: arquivoDasContas) }
        definir(nil)
    }

    private func definir(_ conta: Conta?) {
        atual = conta
        if let conta, let d = try? JSONEncoder().encode(conta) { try? d.write(to: arquivo) } else { try? FileManager.default.removeItem(at: arquivo) }
    }

    private func contasConhecidas() -> [String: Conta] {
        (try? Data(contentsOf: arquivoDasContas)).flatMap { try? JSONDecoder().decode([String: Conta].self, from: $0) } ?? [:]
    }
}
