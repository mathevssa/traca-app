import StoreKit
import SwiftUI
import UserNotifications

// MARK: - Entrar (CMC-007 e CMC-010)

/// Painel de login com a Apple ou o Google, por cima do player pausado ou de Boas-vindas.
/// Login cancelado volta para onde estava, sem mensagem de erro.
struct PainelEntrar: View {
    let tipo: PainelDeEntrar
    let entrar: (Conta.Provedor) -> Void
    let agoraNao: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Capsule().fill(Paleta.neutro600.opacity(0.45)).frame(width: 36, height: 5)
            VStack(alignment: .leading, spacing: 8) {
                switch tipo {
                case .fimDosMinutos(let titulo):
                    Text("SEUS 5 MINUTOS GRÁTIS ACABARAM")
                        .font(Fonte.ui(12, .semibold, relativoA: .caption)).tracking(0.96)
                        .foregroundStyle(Color(hex: 0x8C3410))
                    Text("Seu livro está esperando.")
                        .font(Fonte.marca(28, relativoA: .title)).tracking(-0.56)
                        .foregroundStyle(Cor.texto)
                    Text("Entre para continuar ouvindo \(titulo) de onde parou.")
                        .font(Fonte.ui(16)).foregroundStyle(Color(hex: 0x3D2E25))
                case .jaTenhoConta:
                    Text("Entrar na sua conta")
                        .font(Fonte.marca(28, relativoA: .title)).tracking(-0.56)
                        .foregroundStyle(Cor.texto)
                    Text("Use a mesma conta Apple ou Google que você usou antes.")
                        .font(Fonte.ui(16)).foregroundStyle(Color(hex: 0x3D2E25))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)

            VStack(spacing: 10) {
                Button { entrar(.apple) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "apple.logo").font(.system(size: 19))
                        Text("Entrar com a Apple")
                    }
                    .font(Fonte.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(.black, in: Capsule())
                }
                Button { entrar(.google) } label: {
                    HStack(spacing: 10) {
                        LogoDoGoogle().frame(width: 20, height: 20)
                        Text("Entrar com o Google")
                    }
                    .font(Fonte.headline)
                    .foregroundStyle(Cor.texto)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Cor.fundoElevado.opacity(0.6), in: Capsule())
                    .overlay(Capsule().strokeBorder(Cor.texto, lineWidth: 1.5))
                }
            }

            VStack(spacing: 2) {
                if case .fimDosMinutos = tipo {
                    Text("Depois de entrar, você pode testar 7 dias grátis.")
                        .font(Fonte.caption).foregroundStyle(Color(hex: 0x3D2E25))
                }
                Button("Agora não", action: agoraNao)
                    .font(Fonte.ui(16, .semibold))
                    .foregroundStyle(Color(hex: 0x8C3410))
                    .frame(minHeight: 44)
            }
        }
        .multilineTextAlignment(.leading)
        .padding(EdgeInsets(top: 8, leading: 20, bottom: 18, trailing: 20))
        .vidroDePainel()
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

/// O "G" do Google. A ser trocado pelo asset oficial no desenvolvimento do login (pendência do Atlas).
struct LogoDoGoogle: View {
    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let linha = w * 0.2
            ZStack {
                ForEach(Array(zip([Color(hex: 0xEA4335), Color(hex: 0xFBBC05), Color(hex: 0x34A853), Color(hex: 0x4285F4)],
                                  [(0.62, 0.88), (0.38, 0.62), (0.12, 0.38), (0.0, 0.12)])), id: \.1.0) { cor, faixa in
                    Circle().trim(from: faixa.0, to: faixa.1)
                        .stroke(cor, style: StrokeStyle(lineWidth: linha))
                        .rotationEffect(.degrees(0))
                        .padding(linha / 2)
                }
                Rectangle().fill(Color(hex: 0x4285F4))
                    .frame(width: w * 0.45, height: linha)
                    .offset(x: w * 0.2)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Assinar (CMC-008, ASS-001, ASS-004, ASS-005, ASS-007 a ASS-009)

/// O paywall. Para quem ainda pode testar grátis, mostra a linha do tempo do teste (CMC-008);
/// para quem já usou o teste, o "Assinar" com os benefícios (ASS-001).
struct TelaAssinar: View {
    @Environment(EstadoDoApp.self) private var app
    @Environment(\.dismiss) private var fechar
    @State private var plano: Loja.Plano = .anual
    @State private var comprando = false
    @State private var erroDaCompra: String?
    @State private var alerta: Loja.ResultadoDaRestauracao?

    private var loja: Loja { app.loja }
    private var comTeste: Bool { loja.elegivelAoTeste }
    private var tituloDoLivro: String {
        app.livroDoTocador?.titulo ?? app.biblioteca.livros.first?.titulo ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topo
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Continue ouvindo \(tituloDoLivro)")
                            .font(Fonte.marca(comTeste ? 30 : 31, relativoA: .title))
                            .tracking(-0.6)
                            .foregroundStyle(Cor.texto)
                        Text(comTeste
                             ? "7 dias grátis para ouvir seus livros com o texto acompanhando."
                             : "Seus livros e marcações continuam aqui. Assine para voltar a ouvir de onde parou.")
                            .font(Fonte.ui(16))
                            .foregroundStyle(Paleta.neutro700)
                    }
                    .padding(.trailing, comTeste ? 48 : 0)
                    if comTeste { linhaDoTempo } else { beneficios }
                    planos
                }
                .padding(.horizontal, 24)
                .padding(.top, comTeste ? 16 : 4)
                .padding(.bottom, 24)
            }
            rodape
        }
        .background(Cor.fundo)
        .task { await loja.carregarProdutos() }
        .alert(tituloDoAlerta, isPresented: Binding(get: { alerta != nil && alerta != .restaurada }, set: { if !$0 { alerta = nil } })) {
            Button("OK") { alerta = nil }
        } message: {
            Text(textoDoAlerta)
        }
    }

    // MARK: Partes

    private var topo: some View {
        HStack {
            if !comTeste {
                RoundedRectangle(cornerRadius: 11.7, style: .continuous)
                    .fill(Cor.marca)
                    .frame(width: 52, height: 52)
                    .overlay { DesenhoIcone().stroke(Cor.creme, style: StrokeStyle(lineWidth: 4.4, lineCap: .round)) }
                    .accessibilityHidden(true)
            }
            Spacer()
            Button { fechar() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Cor.texto)
                    .frame(width: 44, height: 44)
            }
            .glassEffect(.regular, in: Circle())
            .accessibilityLabel("Fechar")
        }
        .padding(.horizontal, 12)
        .padding(.leading, comTeste ? 0 : 12)
        .padding(.top, 8)
    }

    /// CMC-008: hoje, dia 5 e dia 7, nesta ordem (fluxo Começar a usar o Traça).
    private var linhaDoTempo: some View {
        VStack(alignment: .leading, spacing: 0) {
            passo(cor: Cor.marca, preenchido: true, negrito: "Hoje:", texto: "acesso completo, sem cobrança", nota: nil, linha: true)
            passo(cor: Cor.acao, preenchido: false, negrito: "Dia 5:", texto: "a gente te lembra que o teste está acabando",
                  nota: "Para isso, vamos pedir permissão para enviar notificações.", linha: true)
            passo(cor: Cor.textoSecundario, preenchido: false, negrito: "Dia 7:", texto: "começa a cobrança. Cancele antes, se quiser", nota: nil, linha: false)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Como funciona o teste")
    }

    private func passo(cor: Color, preenchido: Bool, negrito: String, texto: String, nota: String?, linha: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(preenchido ? cor : Cor.fundo)
                .overlay(Circle().strokeBorder(cor, lineWidth: 2))
                .frame(width: 24, height: 24)
                .background(alignment: .top) {
                    if linha { Rectangle().fill(Paleta.neutro300).frame(width: 2).padding(.top, 26).frame(maxHeight: .infinity).offset(y: 6) }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Text(negrito).bold()) \(texto)")
                    .font(Fonte.ui(16))
                    .foregroundStyle(Cor.texto)
                if let nota {
                    Text(nota).font(Fonte.caption).foregroundStyle(Paleta.neutro700)
                }
            }
            .padding(.top, 1)
        }
        .padding(.bottom, linha ? 14 : 0)
    }

    /// ASS-001: o que a assinatura libera.
    private var beneficios: some View {
        VStack(alignment: .leading, spacing: 10) {
            beneficio("infinity", "Ouça sem limite de horas")
            beneficio("books.vertical", "Importe quantos livros quiser")
            beneficio("text.word.spacing", "O texto acompanha a voz")
            beneficio("bookmark", "Marcações e timer de sono")
        }
    }

    private func beneficio(_ icone: String, _ texto: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icone)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Cor.marca)
                .frame(width: 22)
            Text(texto).font(Fonte.ui(16)).foregroundStyle(Cor.texto)
        }
    }

    @ViewBuilder private var planos: some View {
        VStack(spacing: 10) {
            ForEach(Loja.Plano.allCases, id: \.self) { p in
                cartao(p)
            }
            if loja.preco(.anual) == nil {
                // ASS-004: os cards em esqueleto, sem valor inventado.
                Text("Carregando os preços…")
                    .font(Fonte.caption)
                    .foregroundStyle(Cor.textoSecundario)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Planos")
    }

    private func cartao(_ p: Loja.Plano) -> some View {
        let marcado = plano == p
        return Button { plano = p } label: {
            HStack(spacing: 14) {
                if !comTeste { marcador(marcado) }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(p.nome)
                            .font(Fonte.ui(comTeste ? 15 : 17, .semibold))
                            .foregroundStyle(comTeste ? Paleta.neutro700 : Cor.texto)
                        if p == .anual {
                            Text("20% de desconto")
                                .font(Fonte.ui(12, comTeste ? .bold : .semibold, relativoA: .caption2))
                                .foregroundStyle(comTeste ? Cor.creme : Cor.link)
                                .padding(.horizontal, comTeste ? 8 : 9)
                                .padding(.vertical, comTeste ? 2 : 3)
                                .background(comTeste ? Cor.acao : Paleta.laranja100, in: Capsule())
                        }
                    }
                    if let preco = loja.preco(p) {
                        Text(preco)
                            .font(Fonte.ui(comTeste ? 19 : 16, comTeste ? .bold : .semibold))
                            .foregroundStyle(Cor.texto)
                        if p == .anual, let eq = loja.equivalenteMensal {
                            Text("Equivale a \(eq)")
                                .font(Fonte.ui(comTeste ? 14 : 13, relativoA: .caption))
                                .foregroundStyle(comTeste ? Paleta.neutro700 : Cor.textoSecundario)
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 4).fill(Cor.fundoSutil).frame(width: 140, height: 18)
                    }
                }
                Spacer()
                if comTeste { marcador(marcado) }
            }
            .padding(.horizontal, marcado ? 15 : 16)
            .padding(.vertical, marcado ? 11 : 12)
            .background(marcado ? Cor.fundoElevado : .clear, in: RoundedRectangle(cornerRadius: comTeste ? 20 : 16))
            .overlay(RoundedRectangle(cornerRadius: comTeste ? 20 : 16).strokeBorder(marcado ? Cor.marca : Cor.borda, lineWidth: marcado ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(marcado ? .isSelected : [])
    }

    @ViewBuilder private func marcador(_ marcado: Bool) -> some View {
        if marcado {
            if comTeste {
                Circle().strokeBorder(Cor.marca, lineWidth: 2).frame(width: 24, height: 24)
                    .overlay(Circle().fill(Cor.marca).frame(width: 12, height: 12))
            } else {
                Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Cor.creme)
                    .frame(width: 24, height: 24).background(Cor.marca, in: Circle())
            }
        } else {
            Circle().strokeBorder(comTeste ? Paleta.neutro500 : Paleta.neutro400, lineWidth: 2).frame(width: 24, height: 24)
        }
    }

    private var rodape: some View {
        VStack(spacing: 8) {
            if !app.rede.conectada {
                // ASS-005: assinar precisa de conexão.
                Text("Você está sem internet. Conecte o iPhone para assinar.")
                    .font(Fonte.ui(14, relativoA: .subheadline))
                    .foregroundStyle(Cor.texto)
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(Color(hex: 0xF8E7C4), in: RoundedRectangle(cornerRadius: 16))
            }
            if let erroDaCompra, !erroDaCompra.isEmpty {
                // Compra recusada: o motivo que a App Store devolver.
                Text(erroDaCompra).font(Fonte.caption).foregroundStyle(Cor.erro).frame(maxWidth: .infinity)
            }
            BotaoPrincipal(titulo: comTeste ? "Começar 7 dias grátis" : "Assinar", carregando: comprando) {
                Task { await comprar() }
            }
            .disabled(!app.rede.conectada || loja.preco(plano) == nil || comprando)
            .opacity(!app.rede.conectada || loja.preco(plano) == nil ? 0.5 : 1)

            Text(notaDoPreco)
                .font(Fonte.caption)
                .foregroundStyle(comTeste ? Paleta.neutro700 : Cor.textoSecundario)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            HStack(spacing: 0) {
                link("Restaurar Compras") { Task { await restaurar() } }
                Text("·").foregroundStyle(Cor.textoSecundario).accessibilityHidden(true)
                // Termos e Privacidade: os textos vêm da consulta jurídica (pendência do Atlas).
                link("Termos") {}
                Text("·").foregroundStyle(Cor.textoSecundario).accessibilityHidden(true)
                link("Privacidade") {}
            }
            .font(Fonte.caption)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    private var notaDoPreco: String {
        guard let preco = loja.preco(plano) else { return "Cancele quando quiser nos Ajustes do iPhone." }
        return comTeste
            ? "Depois do teste, \(preco).\nCancele quando quiser nos Ajustes do iPhone"
            : "\(preco), com renovação automática. Cancele quando quiser nos Ajustes do iPhone."
    }

    private func link(_ titulo: String, _ acao: @escaping () -> Void) -> some View {
        Button(titulo, action: acao)
            .foregroundStyle(Cor.link)
            .padding(.horizontal, 6)
            .frame(minHeight: 44)
    }

    // MARK: Ações

    private func comprar() async {
        erroDaCompra = nil
        // O pedido de permissão de notificação vem junto com o lembrete do dia 5.
        if comTeste { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
        comprando = true
        let resultado = await loja.comprar(plano)
        comprando = false
        switch resultado {
        case .ativa:
            app.agendarLembreteDoTeste()
            app.assinaturaMudou()
            fechar()
            app.mostrar(.assinaturaAtiva)
        case .recusada(let motivo):
            erroDaCompra = motivo
        case .desistiu, .pendente:
            break // desistiu: volta para onde estava, sem nada mudar
        }
    }

    private func restaurar() async {
        let r = await loja.restaurar()
        if r == .restaurada {
            app.assinaturaMudou()
            fechar()
            app.mostrar(.assinaturaRestaurada)
        } else {
            alerta = r
        }
    }

    private var tituloDoAlerta: String {
        alerta == .deOutraConta ? "Essa assinatura é de outra conta" : "Nenhuma assinatura encontrada"
    }

    private var textoDoAlerta: String {
        alerta == .deOutraConta
            ? "Ela foi comprada com outra conta do Traça neste iPhone. Entre com aquela conta para usar."
            : "Não encontramos uma assinatura do Traça nesta conta Apple."
    }
}
