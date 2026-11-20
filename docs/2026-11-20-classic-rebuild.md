# Reformulação clássica, 2026-11-20

Pedido: substituir o jogo circular por um jogo de blocos inspirado no Tetris dos anos 90.

## Implementação

- Campo retangular com 10 colunas, 20 linhas visíveis e 2 linhas de entrada.
- Sete peças de quatro blocos (I, O, T, S, Z, J, L), cada uma com cor própria.
- Paredes fixas, gravidade vertical, rotação sem wall/floor kicks e aparecimento ao centro.
- Limpeza de linhas completas, deslocação conjunta das linhas superiores, sem fusões por cor ou poderes.
- Pontos de linha: 40/100/300/1200 multiplicados pelo nível. Progressão a cada 10 linhas.
- Uma peça seguinte. Saco de sete, atraso ao pousar e queda imediata são concessões de jogabilidade tátil; não se pretende emular uma edição específica.
- Clássico, 40 linhas e 2 minutos. Três exercícios resolvíveis com as regras novas.
- Guia de queda desligado e botões ligados por defeito em novas instalações; preferências existentes respeitadas.
- Paleta azul-escuro, blocos com relevo, molduras retas, fonte monoespaçada e HUD compacto.
- Dados circulares preservados nos ficheiros anteriores. Novos ficheiros classic-saved-run.json/classic-stats.json, snapshot versão 3.

## Verificação

Build e suite XCTest no iPhone 17 Pro, iOS 26.4. Casos de paredes, quatro rotações, quatro linhas, cor sem efeito, gravidade, pausa, retoma, fila, treino, meta de 40 linhas, fim por tempo e topo bloqueado. Testes de interface renderizam telefone pequeno e tablet, incluindo aspeto claro, treino e menu. A geração de capturas da loja continua opcional.

Não foi feita publicação, upload para TestFlight nem alteração no App Store Connect. Falta a apreciação do David sobre o toque e o ritmo num dispositivo físico.
