# Traça · app

O código do Traça, o app de iPhone que transforma os livros do próprio leitor em audiolivro, com o texto na tela acompanhando a voz.

O que o app faz, as regras e as telas estão no [Atlas do Traça](https://github.com/mathevssa/atlas-traca-app). O código segue o Atlas: se os dois discordam, vale o Atlas, e a divergência é levada ao Matheus.

## Como o trabalho anda

O app é construído em fases, cada uma testada no iPhone do Matheus antes da próxima:

1. **Fase 0 · riscos técnicos:** PDF com texto fora de ordem, arquivos MOBI e AZW3, texto acompanhando a voz palavra por palavra.
2. **Fase 1 · o coração:** importar um livro, gerar a voz em trechos, tocar com o texto acompanhando e com a tela bloqueada. Começa com a voz do próprio iPhone, provisória, e troca pela Inworld quando a chave estiver pronta.
3. **Fase 2 · o app de quem ouve:** biblioteca, busca, todos os formatos, capítulos, marcações, velocidade, vozes e timer.
4. **Fase 3 · conta e assinatura:** login com Apple e Google, os 5 minutos grátis, o teste de 7 dias, os planos e o painel. Depende da conta de desenvolvedor da Apple.
5. **Fase 4 · acabamento e envio:** conferência das 55 telas contra o canvas, privacidade, teste com leitores pelo TestFlight e envio para a revisão da Apple.

## O projeto

- Abra `Traca.xcodeproj` no Xcode 26 ou mais novo.
- Identificador do app: `app.traca.ios`. Não muda depois de publicado.
- Só iPhone, iOS 26 no mínimo, só em retrato e sempre no modo claro.
- Fontes da marca (Young Serif e Hanken Grotesk) ficam em `Traca/Fontes`, com as licenças OFL.
- Livros de teste ficam fora do Git, em `~/Documents/traca-livros-teste`.

## Ferramentas

- App nativo em SwiftUI, só iPhone, com o Liquid Glass do iOS 26.
- Voz: Inworld TTS.
- Servidor: a definir na Fase 3 (proposta: Supabase).
- Assinaturas: StoreKit 2, com a forma de receber os avisos da Apple a definir pelo Matheus (RevenueCat por baixo ou integração direta).
