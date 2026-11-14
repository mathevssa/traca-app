import StoreKit
import SwiftUI
import UserNotifications

/// Conta (CON-001, CON-004, CON-005): o e-mail, o provedor, a assinatura, as notificações,
/// sair e excluir a conta (CON-002, CON-003, CON-006).
struct TelaConta: View {
    @Environment(EstadoDoApp.self) private var app
    @Environment(\.dismiss) private var fechar
    @Environment(\.openURL) private var abrirURL
    @State private var avisosLigados = false
    @State private var excluindoConta = false
    @State private var excluindoAgora = false
    @State private var semInternet = false
    @State private var gerenciando = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Conta")
                    .font(Fonte.ui(34, .bold, relativoA: .largeTitle))
                    .foregroundStyle(Cor.texto)
                    .padding(.top, 4)
                if let conta = app.contas.atual {
                    secao("Entrou como") {
                        HStack(spacing: 14) {
                            Image(systemName: "person")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(Cor.texto)
                                .frame(width: 44, height: 44)
                                .background(Cor.fundoSutil, in: Circle())
                            Text("\(conta.email) · \(conta.provedor.rawValue)")
                                .font(Fonte.ui(16, .semibold))
                                .foregroundStyle(Cor.texto)
                                .lineLimit(1)
                        }
                        .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    assinatura
                    notificacoes(conta)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .safeAreaInset(edge: .top) { voltar }
        .safeAreaInset(edge: .bottom) { rodape }
        .background(Cor.fundo)
        .toolbar(.hidden, for: .navigationBar)
        .overlay { if excluindoConta { dialogoExcluir } }
        .manageSubscriptionsSheet(isPresented: $gerenciando)
        .task { await atualizarAvisos() }
    }

    private var voltar: some View {
        HStack {
            Button { fechar() } label: {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold))
                    Text("Biblioteca").font(Fonte.ui(16, .medium))
                }
                .foregroundStyle(Cor.texto)
                .padding(.leading, 6)
                .padding(.trailing, 14)
                .frame(height: 44)
            }
            .glassEffect(.regular, in: Capsule())
            Spacer()
        }
        .padding(.horizontal, 12)
        .background(Cor.fundo.opacity(0.92))
    }

    private func secao<C: View>(_ titulo: String, @ViewBuilder _ conteudo: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Sobretitulo(texto: titulo)
            conteudo()
                .background(Cor.fundoElevado, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    // MARK: Assinatura

    @ViewBuilder private var assinatura: some View {
        let s = app.loja.situacao
        VStack(alignment: .leading, spacing: 8) {
            secao("Assinatura") {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(plano(s)?.nome ?? "").font(Fonte.ui(17, .semibold)).foregroundStyle(Cor.texto)
                            if let (texto, cor, fundo) = selo(s) {
                                Text(texto)
                                    .font(Fonte.ui(12, .semibold, relativoA: .caption2))
                                    .foregroundStyle(cor)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 3)
                                    .background(fundo, in: Capsule())
                            }
                        }
                        if let linha = linha(s) {
                            Text(linha).font(Fonte.ui(14, relativoA: .subheadline)).foregroundStyle(Paleta.neutro700)
                        }
                    }
                    .padding(EdgeInsets(top: 16, leading: 16, bottom: 14, trailing: 16))
                    if mostraAssinar(s) {
                        BotaoPrincipal(titulo: "Assinar") { app.mostrandoAssinar = true }
                            .padding(EdgeInsets(top: 0, leading: 16, bottom: 16, trailing: 16))
                    } else {
                        Rectangle().fill(Cor.fundoSutil).frame(height: 1).padding(.horizontal, 16)
                        Button { gerenciando = true } label: {
                            HStack {
                                Text("Gerenciar assinatura")
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold))
                            }
                            .font(Fonte.ui(16, .semibold))
                            .foregroundStyle(Cor.link)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 52)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !mostraAssinar(s) {
                Text("Troque de plano ou cancele nos Ajustes do iPhone.")
                    .font(Fonte.caption)
                    .foregroundStyle(Cor.textoSecundario)
                    .padding(.horizontal, 4)
            }
        }
    }

    private func plano(_ s: Loja.Situacao) -> Loja.Plano? {
        switch s {
        case .emTeste(let p, _), .ativa(let p, _), .carencia(let p), .expirada(let p, _): p
        case .semAssinatura: nil
        }
    }

    private func mostraAssinar(_ s: Loja.Situacao) -> Bool {
        switch s {
        case .expirada, .semAssinatura: true
        default: false
        }
    }

    /// Selos da Conta (fluxo Gerenciar a conta): "Ativa", "Teste grátis", "Expirada".
    private func selo(_ s: Loja.Situacao) -> (String, Color, Color)? {
        switch s {
        case .ativa, .carencia: ("Ativa", Cor.sucesso, Color(hex: 0xE3EBD3))
        case .emTeste: ("Teste grátis", Cor.link, Paleta.laranja100)
        case .expirada: ("Expirada", Cor.alerta, Color(hex: 0xF8E7C4))
        case .semAssinatura: nil
        }
    }

    private func linha(_ s: Loja.Situacao) -> String? {
        switch s {
        case .ativa(let p, let d):
            guard let d, let preco = app.loja.produtos[p]?.displayPrice else { return nil }
            return "Próxima cobrança: \(preco) em \(dataLonga(d))"
        case .emTeste(let p, let fim):
            guard let fim, let preco = app.loja.preco(p) else { return nil }
            return "Seu teste termina em \(dataCurta(fim)). Depois, \(preco)."
        case .expirada(_, let fim):
            guard let fim else { return nil }
            return "Sua assinatura terminou em \(dataCurta(fim))."
        default:
            return nil
        }
    }

    /// "18 de outubro de 2027"
    private func dataLonga(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "d 'de' MMMM 'de' yyyy"
        return f.string(from: d)
    }

    /// "17 de novembro"
    private func dataCurta(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "d 'de' MMMM"
        return f.string(from: d)
    }

    // MARK: Notificações

    private func notificacoes(_ conta: Conta) -> some View {
        secao("Notificações") {
            VStack(spacing: 0) {
                Toggle(isOn: Binding(get: { avisosLigados }, set: { ligar in Task { await mudarAvisos(ligar) } })) {
                    Text("Avisos no iPhone").font(Fonte.ui(16, .medium)).foregroundStyle(Cor.texto)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                Rectangle().fill(Cor.fundoSutil).frame(height: 1).padding(.horizontal, 16)
                Toggle(isOn: Binding(get: { conta.aceitaEmails }, set: { v in app.contas.atualizar { $0.aceitaEmails = v } })) {
                    Text("Novidades por e-mail").font(Fonte.ui(16, .medium)).foregroundStyle(Cor.texto)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
            }
            .tint(Cor.acao)
        }
    }

    private func atualizarAvisos() async {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        avisosLigados = s.authorizationStatus == .authorized && !UserDefaults.standard.bool(forKey: "avisosDesligados")
    }

    /// Se o leitor negou a permissão no iOS, ligar abre os Ajustes do iPhone, porque só lá dá para mudar.
    private func mudarAvisos(_ ligar: Bool) async {
        let centro = UNUserNotificationCenter.current()
        let s = await centro.notificationSettings()
        if ligar {
            switch s.authorizationStatus {
            case .denied:
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { abrirURL(url) }
            case .notDetermined:
                _ = try? await centro.requestAuthorization(options: [.alert, .sound])
            default: break
            }
            UserDefaults.standard.set(false, forKey: "avisosDesligados")
        } else {
            UserDefaults.standard.set(true, forKey: "avisosDesligados")
            centro.removeAllPendingNotificationRequests()
        }
        await atualizarAvisos()
    }

    // MARK: Sair e excluir

    private var rodape: some View {
        VStack(spacing: 6) {
            Button { app.sair() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.portrait.and.arrow.right").font(.system(size: 17, weight: .semibold))
                    Text("Sair")
                }
                .font(Fonte.headline)
                .foregroundStyle(Cor.texto)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Cor.fundoSutil, in: Capsule())
            }
            Button("Excluir conta") {
                semInternet = false
                withAnimation(.spring(duration: 0.35)) { excluindoConta = true }
            }
            .font(Fonte.ui(15, .medium))
            .foregroundStyle(Cor.erro)
            .frame(minHeight: 44)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .background(Cor.fundo)
    }

    /// CON-002: o que o leitor perde e o aviso de que a assinatura da App Store continua.
    private var dialogoExcluir: some View {
        ZStack(alignment: .bottom) {
            Escurecimento { if !excluindoAgora { withAnimation { excluindoConta = false } } }
            VStack(alignment: .leading, spacing: 12) {
                Capsule().fill(Paleta.neutro300).frame(width: 36, height: 5).frame(maxWidth: .infinity).padding(.bottom, 6)
                Text("Excluir sua conta?").font(Fonte.ui(24, .bold, relativoA: .title2)).foregroundStyle(Cor.texto)
                Text("Ao excluir, você perde:").font(Fonte.ui(15, relativoA: .callout)).foregroundStyle(Paleta.neutro700)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(["Seus livros", "Suas marcações", "Onde você parou em cada livro"], id: \.self) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Circle().fill(Cor.marca).frame(width: 6, height: 6).padding(.top, 8)
                            Text(item).font(Fonte.ui(15, relativoA: .callout)).foregroundStyle(Cor.texto)
                        }
                    }
                }
                Text("Não dá para desfazer.").font(Fonte.ui(15, .semibold, relativoA: .callout)).foregroundStyle(Cor.texto)
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(Cor.alerta)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Excluir a conta não cancela sua assinatura da App Store. Ela continua até você cancelar.")
                            .font(Fonte.ui(14, relativoA: .subheadline)).foregroundStyle(Cor.texto)
                        Button { gerenciando = true } label: {
                            HStack(spacing: 6) {
                                Text("Cancelar assinatura nos Ajustes do iPhone").multilineTextAlignment(.leading)
                                Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .semibold))
                            }
                            .font(Fonte.ui(14, .semibold, relativoA: .subheadline))
                            .foregroundStyle(Cor.link)
                            .frame(minHeight: 32)
                        }
                    }
                }
                .padding(14)
                .background(Color(hex: 0xF8E7C4), in: RoundedRectangle(cornerRadius: 16))
                if semInternet {
                    // CON-006: nada é apagado sem internet.
                    HStack(spacing: 12) {
                        Image(systemName: "wifi.slash").foregroundStyle(Cor.erro)
                        Text("Você está sem internet. Conecte o iPhone para excluir a conta.")
                            .font(Fonte.ui(15, relativoA: .callout)).foregroundStyle(Cor.texto)
                    }
                    .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 12))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 20))
                }
                VStack(spacing: 8) {
                    Button {
                        Task {
                            excluindoAgora = true
                            semInternet = false
                            let ok = await app.excluirConta()
                            excluindoAgora = false
                            if !ok { semInternet = true }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            if excluindoAgora { ProgressView().tint(Cor.creme) }
                            Text(excluindoAgora ? "Excluindo sua conta…" : "Excluir conta")
                        }
                        .font(Fonte.headline)
                        .foregroundStyle(Cor.creme)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Cor.erro, in: Capsule())
                    }
                    .disabled(excluindoAgora)
                    if excluindoAgora {
                        // CON-003: enquanto a exclusão acontece, o diálogo não pode ser fechado.
                        Text("Leva alguns segundos. Não feche o Traça até terminar.")
                            .font(Fonte.caption).foregroundStyle(Paleta.neutro700)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                    } else {
                        Button { withAnimation { excluindoConta = false } } label: {
                            Text("Manter minha conta")
                                .font(Fonte.headline)
                                .foregroundStyle(Cor.texto)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(.white.opacity(0.55), in: Capsule())
                                .overlay(Capsule().strokeBorder(Cor.texto.opacity(0.08)))
                        }
                    }
                }
                .padding(.top, 4)
            }
            .padding(EdgeInsets(top: 10, leading: 20, bottom: 20, trailing: 20))
            .vidroDePainel()
            .padding(8)
            .transition(.move(edge: .bottom))
            .accessibilityAddTraits(.isModal)
        }
    }
}
