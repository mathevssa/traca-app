import AVFoundation
import SwiftUI

/// Escolher a voz (CMC-004): o livro recém-importado, a lista de vozes com amostra
/// e a primeira já marcada. Ao confirmar, o player abre e a narração começa sozinha.
struct TelaEscolherVoz: View {
    let livroID: UUID
    @Environment(EstadoDoApp.self) private var app
    @State private var vozes: [OpcaoDeVoz] = []
    @State private var escolhida: String?
    @State private var amostra = Amostra()

    private var livro: LivroGuardado? { app.biblioteca.livros.first { $0.id == livroID } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let livro {
                    HStack(spacing: 14) {
                        CapaDoLivro(titulo: livro.titulo, imagem: app.biblioteca.capa(de: livro), raio: 8, tamanhoDoTitulo: 12)
                            .frame(width: 60, height: 86)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                                Text("LIVRO IMPORTADO").tracking(0.96)
                            }
                            .font(Fonte.ui(12, .semibold, relativoA: .caption))
                            .foregroundStyle(Cor.sucesso)
                            Text(livro.titulo)
                                .font(Fonte.marca(22, relativoA: .title2))
                                .tracking(-0.44)
                                .foregroundStyle(Cor.texto)
                            if let autor = livro.autor {
                                Text(autor).font(Fonte.ui(14, relativoA: .subheadline)).foregroundStyle(Cor.textoSecundario)
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Escolha a voz")
                        .font(Fonte.marca(30, relativoA: .title))
                        .tracking(-0.6)
                        .foregroundStyle(Cor.texto)
                    Text("Ouça uma amostra de cada uma. Dá para trocar depois.")
                        .font(Fonte.ui(16))
                        .foregroundStyle(Paleta.neutro700)
                }
                VStack(spacing: 10) {
                    ForEach(vozes) { voz in linha(voz) }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Vozes em português do Brasil")
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 160)
        }
        .background(Cor.fundo)
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .bottom) { confirmar }
        .onAppear {
            vozes = VozDoIPhone().vozes
            // A primeira voz da lista vem pré-selecionada (fluxo Começar a usar o Traça).
            escolhida = escolhida ?? vozes.first?.id
        }
        .onDisappear { amostra.parar() }
    }

    private func linha(_ voz: OpcaoDeVoz) -> some View {
        let marcada = escolhida == voz.id
        let tocando = amostra.tocando == voz.id
        return HStack(spacing: 14) {
            Button {
                tocando ? amostra.parar() : amostra.tocar(voz.id, texto: textoDaAmostra)
            } label: {
                Image(systemName: tocando ? "pause.fill" : "play.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Cor.marca)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular, in: Circle())
            }
            .accessibilityLabel(tocando ? "Pausar a amostra de \(voz.nome)" : "Ouvir a amostra de \(voz.nome)")

            Button { escolhida = voz.id } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(voz.nome)
                            .font(Fonte.ui(17, .semibold, relativoA: .headline))
                            .foregroundStyle(Cor.texto)
                        if tocando {
                            HStack(spacing: 6) {
                                Image(systemName: "waveform").font(.system(size: 12, weight: .semibold))
                                Text("Tocando a amostra")
                            }
                            .font(Fonte.ui(13, .semibold, relativoA: .caption))
                            .foregroundStyle(Cor.link)
                        }
                    }
                    Spacer()
                    Circle()
                        .strokeBorder(marcada ? Cor.marca : Paleta.neutro500, lineWidth: 2)
                        .frame(width: 24, height: 24)
                        .overlay { if marcada { Circle().fill(Cor.marca).frame(width: 12, height: 12) } }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(marcada ? .isSelected : [])
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(marcada ? Cor.fundoElevado : .clear, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(marcada ? Cor.marca : Cor.borda, lineWidth: marcada ? 2 : 1))
    }

    private var confirmar: some View {
        VStack(spacing: 8) {
            let nome = vozes.first { $0.id == escolhida }?.nome ?? ""
            BotaoPrincipal(titulo: "Começar a ouvir com \(nome)", icone: "play.fill") {
                amostra.parar()
                EstadoDoApp.idDaVozEscolhida = escolhida
                if let livro { app.abrir(livro) }
            }
            Text("5 minutos grátis, sem cadastro.")
                .font(Fonte.ui(13, relativoA: .caption))
                .foregroundStyle(Paleta.neutro700)
                .padding(.bottom, 4)
        }
        .padding(12)
        .vidroDePainel()
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }

    /// A amostra lê o começo do próprio livro do leitor.
    private var textoDaAmostra: String {
        guard let livro, let texto = app.biblioteca.texto(de: livro) else { return "" }
        var amostra = ""
        for p in texto.paragrafos where p.tipo == .corpo && p.texto.count > 40 {
            amostra = p.frases.prefix(2).map { (p.texto as NSString).substring(with: $0) }.joined()
            break
        }
        return amostra
    }
}

/// Toca a amostra de uma voz direto no alto-falante.
@Observable
final class Amostra: NSObject, AVSpeechSynthesizerDelegate {
    private(set) var tocando: String?
    private let sintetizador = AVSpeechSynthesizer()

    override init() {
        super.init()
        sintetizador.delegate = self
    }

    func tocar(_ voz: String, texto: String) {
        parar()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        let fala = AVSpeechUtterance(string: texto)
        fala.voice = AVSpeechSynthesisVoice(identifier: voz)
        tocando = voz
        sintetizador.speak(fala)
    }

    func parar() {
        sintetizador.stopSpeaking(at: .immediate)
        tocando = nil
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.tocando = nil }
    }
}
