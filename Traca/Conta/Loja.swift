import Foundation
import Observation
import StoreKit

/// A assinatura do Traça pela App Store (objeto Assinatura), com o StoreKit 2.
/// Os dois produtos à venda são o Plano mensal e o Plano anual, com 7 dias grátis.
@Observable
final class Loja {
    enum Plano: String, CaseIterable {
        case anual = "app.traca.ios.anual"
        case mensal = "app.traca.ios.mensal"

        var nome: String { self == .anual ? "Plano anual" : "Plano mensal" }
    }

    /// O estado da assinatura da conta que está no aparelho (objeto Assinatura, ciclo de vida).
    enum Situacao: Equatable {
        /// Ainda não começou o teste grátis.
        case semAssinatura
        case emTeste(Plano, fim: Date?)
        case ativa(Plano, proximaCobranca: Date?)
        /// Cobrança recusada: a App Store tenta de novo por 16 dias.
        case carencia(Plano)
        case expirada(Plano, fim: Date?)
    }

    enum ResultadoDaCompra: Equatable {
        case ativa
        case desistiu
        case pendente
        case recusada(String)
    }

    enum ResultadoDaRestauracao {
        case restaurada
        case nadaEncontrado
        case deOutraConta
    }

    private(set) var produtos: [Plano: Product] = [:]
    private(set) var carregandoPrecos = false
    /// Quem já usou o teste grátis na conta Apple não vê oferta de teste (fluxo Assinar o Traça).
    private(set) var elegivelAoTeste = true
    private(set) var situacao: Situacao = .semAssinatura
    /// A conta do Traça logada. A assinatura fica ligada à conta que estava logada na compra.
    var conta: UUID? {
        didSet { Task { await atualizar() } }
    }

    private var escuta: Task<Void, Never>?

    init() {
        escuta = Task { [weak self] in
            for await _ in Transaction.updates {
                await self?.atualizar()
            }
        }
    }

    // MARK: Preços

    func carregarProdutos() async {
        guard produtos.count < Plano.allCases.count else { return }
        carregandoPrecos = true
        defer { carregandoPrecos = false }
        guard let lista = try? await Product.products(for: Plano.allCases.map(\.rawValue)) else { return }
        for p in lista { if let plano = Plano(rawValue: p.id) { produtos[plano] = p } }
        if let p = produtos[.anual] { elegivelAoTeste = await p.subscription?.isEligibleForIntroOffer ?? false }
        await atualizar()
    }

    /// "R$ 429,90 por ano" ou "R$ 44,90 por mês".
    func preco(_ plano: Plano) -> String? {
        guard let p = produtos[plano] else { return nil }
        return p.displayPrice + (plano == .anual ? " por ano" : " por mês")
    }

    /// O equivalente por mês do plano anual, como informação secundária (exigência da App Store).
    var equivalenteMensal: String? {
        guard let p = produtos[.anual] else { return nil }
        return (p.price / 12).formatted(p.priceFormatStyle) + " por mês"
    }

    // MARK: Situação

    /// Lê da App Store o estado da assinatura desta conta.
    func atualizar() async {
        var produto = produtos.values.first
        if produto == nil { produto = (try? await Product.products(for: [Plano.anual.rawValue]))?.first }
        guard let produto, let estados = try? await produto.subscription?.status else { return }
        if let p = produtos[.anual] { elegivelAoTeste = await p.subscription?.isEligibleForIntroOffer ?? elegivelAoTeste }
        // Só vale a assinatura comprada com esta conta do Traça.
        let daConta = estados.filter { e in
            guard case .verified(let t) = e.transaction else { return false }
            return t.appAccountToken == conta && conta != nil
        }
        guard let estado = daConta.max(by: { prioridade($0.state) < prioridade($1.state) }),
              case .verified(let t) = estado.transaction else {
            situacao = .semAssinatura
            return
        }
        let plano = Plano(rawValue: t.productID) ?? .anual
        switch estado.state {
        case .subscribed:
            situacao = t.offer?.type == .introductory ? .emTeste(plano, fim: t.expirationDate) : .ativa(plano, proximaCobranca: t.expirationDate)
        case .inGracePeriod, .inBillingRetryPeriod:
            situacao = .carencia(plano)
        default:
            situacao = .expirada(plano, fim: t.expirationDate ?? t.revocationDate)
        }
    }

    private func prioridade(_ s: Product.SubscriptionInfo.RenewalState) -> Int {
        switch s {
        case .subscribed: 4
        case .inGracePeriod: 3
        case .inBillingRetryPeriod: 2
        default: 1
        }
    }

    // MARK: Comprar e restaurar

    /// Compra pela App Store, ligando a compra à conta do Traça logada.
    func comprar(_ plano: Plano) async -> ResultadoDaCompra {
        guard let produto = produtos[plano], let conta else { return .recusada("") }
        do {
            switch try await produto.purchase(options: [.appAccountToken(conta)]) {
            case .success(let verificacao):
                guard case .verified(let t) = verificacao else { return .recusada("") }
                await t.finish()
                await atualizar()
                return .ativa
            case .userCancelled: return .desistiu
            case .pending: return .pendente
            @unknown default: return .desistiu
            }
        } catch {
            return .recusada(error.localizedDescription)
        }
    }

    /// "Restaurar Compras" (fluxo Assinar o Traça): três respostas possíveis.
    func restaurar() async -> ResultadoDaRestauracao {
        // Pede à App Store as compras desta conta Apple, sem esperar mais de 20 segundos.
        await withTaskGroup(of: Void.self) { grupo in
            grupo.addTask { try? await AppStore.sync() }
            grupo.addTask { try? await Task.sleep(for: .seconds(20)) }
            await grupo.next()
            grupo.cancelAll()
        }
        await atualizar()
        if case .emTeste = situacao { return .restaurada }
        if case .ativa = situacao { return .restaurada }
        // Há assinatura válida nesta conta Apple, mas comprada com outra conta do Traça?
        for await resultado in Transaction.currentEntitlements {
            if case .verified(let t) = resultado, Plano(rawValue: t.productID) != nil, t.appAccountToken != conta {
                return .deOutraConta
            }
        }
        return .nadaEncontrado
    }
}
