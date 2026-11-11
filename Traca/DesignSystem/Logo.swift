import SwiftUI

/// O desenho do ícone (livro aberto com cinco barras), no viewBox 100 do canvas.
struct DesenhoIcone: Shape {
    func path(in r: CGRect) -> Path {
        let k = min(r.width, r.height) / 100
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * k, y: r.minY + y * k) }
        var path = Path()
        path.move(to: p(14, 77))
        path.addQuadCurve(to: p(50, 77), control: p(32, 67))
        path.addQuadCurve(to: p(86, 77), control: p(68, 67))
        for (x, a, b) in [(28.0, 58.0, 48.0), (39, 60, 36), (50, 62, 23), (61, 60, 34), (72, 58, 46)] {
            path.move(to: p(x, a)); path.addLine(to: p(x, b))
        }
        return path
    }
}

/// Logotipo, versão invertida: ícone laranja com desenho creme e o nome "traça" em laranja.
struct Logotipo: View {
    var tamanho: CGFloat = 48

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: tamanho * 0.225, style: .continuous)
                .fill(Cor.marca)
                .overlay {
                    DesenhoIcone()
                        .stroke(Cor.creme, style: StrokeStyle(lineWidth: tamanho * 0.085, lineCap: .round))
                }
                .frame(width: tamanho, height: tamanho)
            Text("traça")
                .font(Fonte.marca(tamanho * 0.71))
                .tracking(-0.04 * tamanho * 0.71)
                .foregroundStyle(Cor.marca)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Traça")
    }
}
