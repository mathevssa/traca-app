import Foundation
import StoreKitTest
import Testing
@testable import Traca

/// A assinatura com a loja de teste do Xcode (Traca.storekit), num roteiro único com uma compra só:
/// preços do Atlas, restaurar sem compra, começar o teste grátis, e a regra de que a assinatura
/// pertence à conta do Traça que estava logada na compra.
@MainActor
struct LojaTests {
    /// Desligado na bateria completa: lá o próprio app abre a loja ao iniciar e briga com a loja
    /// de teste, e os preços chegam vazios. Para rodar, use só este teste:
    /// xcodebuild test -only-testing:TracaTests/LojaTests (com TRACA_TESTAR_LOJA=1 no esquema).
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TRACA_TESTAR_LOJA"] != nil))
    func roteiroDaAssinatura() async throws {
        let bundle = try #require(Bundle.allBundles.first { $0.bundlePath.hasSuffix(".xctest") })
        let url = try #require(bundle.url(forResource: "Traca", withExtension: "storekit"))
        let sessao = try SKTestSession(contentsOf: url)
        sessao.disableDialogs = true
        sessao.clearTransactions()

        let loja = Loja()
        let conta = UUID()
        loja.conta = conta
        await loja.carregarProdutos()

        // Os dois planos, com os preços do Atlas, e o teste grátis disponível.
        #expect(loja.produtos[.anual]?.price == Decimal(string: "429.9"))
        #expect(loja.produtos[.mensal]?.price == Decimal(string: "44.9"))
        #expect(loja.elegivelAoTeste)

        // Restaurar sem nenhuma compra: "Nenhuma assinatura encontrada".
        #expect(await loja.restaurar() == .nadaEncontrado)

        // Assinar o Plano anual começa o teste grátis nesta conta.
        #expect(await loja.comprar(.anual) == .ativa)
        guard case .emTeste(.anual, _) = loja.situacao else {
            Issue.record("Esperava teste grátis, veio \(loja.situacao)")
            return
        }

        // Outra conta do Traça no mesmo iPhone, com a mesma conta Apple que pagou: não ganha acesso.
        loja.conta = UUID()
        await loja.atualizar()
        #expect(loja.situacao == .semAssinatura)
        #expect(await loja.restaurar() == .deOutraConta)

        sessao.clearTransactions()
    }
}
