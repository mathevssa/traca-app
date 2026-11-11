import Foundation
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// RTF, lido pelo próprio sistema. Linhas com letra bem maior que o texto viram títulos de capítulo.
nonisolated enum LeitorRTF {
    static func ler(_ dados: Data) throws -> LivroLido {
        guard let doc = try? NSAttributedString(data: dados, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) else {
            throw ErroDeLeitura.corrompido
        }
        let s = doc.string as NSString
        var paragrafos: [(texto: String, tamanho: CGFloat)] = []
        s.enumerateSubstrings(in: NSRange(location: 0, length: s.length), options: .byParagraphs) { sub, r, _, _ in
            guard let sub, !sub.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            var maior: CGFloat = 0
            doc.enumerateAttribute(.font, in: r) { v, _, _ in
                #if canImport(UIKit)
                if let f = v as? UIFont { maior = max(maior, f.pointSize) }
                #else
                if let f = v as? NSFont { maior = max(maior, f.pointSize) }
                #endif
            }
            paragrafos.append((sub, maior))
        }
        // O tamanho de letra mais comum é o do texto do livro.
        let contagem = Dictionary(paragrafos.map { ($0.tamanho, $0.texto.count) }, uniquingKeysWith: +)
        let corpo = contagem.max { $0.value < $1.value }?.key ?? 12
        var ps: [Paragrafo] = []
        var caps: [Capitulo] = []
        for p in paragrafos {
            let titulo = p.tamanho >= corpo * 1.3 && p.texto.count <= 120
            if titulo { caps.append(Capitulo(titulo: TextoDoLivro.normalizarEspacos(p.texto), primeiroParagrafo: ps.count)) }
            ps.append(Paragrafo(texto: p.texto, tipo: titulo ? .titulo : .corpo))
        }
        if caps.count < 2 { caps = ReconhecedorDeCapitulos.reconhecer(em: ps) }
        return LivroLido(titulo: nil, autor: nil, capa: nil, formato: .rtf, texto: TextoDoLivro(paragrafos: ps, capitulos: caps))
    }
}
