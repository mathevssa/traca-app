import Foundation
import Security

/// Guarda pequenos valores no chaveiro do iPhone, que sobrevive à reinstalação do app.
/// É assim que os 5 minutos grátis valem uma vez por aparelho (fluxo Começar a usar o Traça).
nonisolated enum Chaveiro {
    private static let servico = "app.traca.ios"

    static func ler(_ chave: String) -> Data? {
        let busca: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: servico,
            kSecAttrAccount as String: chave,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var resultado: AnyObject?
        guard SecItemCopyMatching(busca as CFDictionary, &resultado) == errSecSuccess else { return nil }
        return resultado as? Data
    }

    static func gravar(_ dados: Data, em chave: String) {
        let busca: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: servico,
            kSecAttrAccount as String: chave,
        ]
        let novo: [String: Any] = [
            kSecValueData as String: dados,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        if SecItemUpdate(busca as CFDictionary, novo as CFDictionary) == errSecItemNotFound {
            SecItemAdd(busca.merging(novo) { $1 } as CFDictionary, nil)
        }
    }
}

/// Os 5 minutos grátis do aparelho: quanto a voz já tocou e quanto já foi gerado
/// (objeto Narração, permissões "Antes do teste").
nonisolated struct MinutosGratis: Codable {
    static let limite: TimeInterval = 5 * 60

    var tocados: TimeInterval = 0
    var gerados: TimeInterval = 0
    /// Impressão digital do livro que ganhou os 5 minutos.
    var livro: String?

    var restantes: TimeInterval { max(0, Self.limite - tocados) }
    var acabaram: Bool { tocados >= Self.limite }

    static func carregar() -> MinutosGratis {
        Chaveiro.ler("minutosGratis").flatMap { try? JSONDecoder().decode(MinutosGratis.self, from: $0) } ?? MinutosGratis()
    }

    func salvar() {
        if let d = try? JSONEncoder().encode(self) { Chaveiro.gravar(d, em: "minutosGratis") }
    }
}
