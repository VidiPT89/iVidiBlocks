# iVidiBlocks

Jogo de blocos para iPhone e iPad, inspirado nos jogos de consola dos anos 90. SwiftUI, SpriteKit e motor de regras independente da interface.

## Jogo

- Tabuleiro vertical de 10 × 20, com paredes e sete tetraminós.
- Só linhas horizontais completas desaparecem. Não há fusões por cor, cascatas nem poderes.
- Pontuação por 1/2/3/4 linhas: 40/100/300/1200 × nível.
- Clássico: velocidade progressiva a cada 10 linhas. Modos adicionais: 40 linhas e 2 minutos.
- Uma próxima peça visível, distribuição em sacos de sete para evitar secas prolongadas.
- Rotação sem deslocações automáticas junto às paredes. Pequeno atraso ao pousar para controlos táteis.
- Botões direcionais com repetição, duas rotações, queda manual e queda imediata.
- Guia de queda opcional, desativado por defeito. Sem reserva de peças.
- Três exercícios guiados, pausa, retoma, estatísticas locais e idiomas PT-PT/EN.
- Blocos quadrados com relevo, moldura, fundo escuro e contadores monoespaçados.

## Controlos

| Ação | Gesto ou botão |
|---|---|
| Mover | Arrastar para os lados ou manter uma seta premida |
| Rodar | Tocar no lado esquerdo/direito do tabuleiro ou usar os botões de rotação |
| Descer | Arrastar para baixo ou manter a seta para baixo premida |
| Queda imediata | Deslizar rapidamente para baixo ou botão de queda |
| Pausa | Botão no topo; automática ao sair da app |

## Desenvolvimento

Abrir `iVidiBlocks.xcodeproj` no Xcode e executar o scheme `iVidiBlocks`. Requer iOS 17+. O projeto é gerado a partir de `project.yml` com XcodeGen.

```sh
xcodebuild -project iVidiBlocks.xcodeproj -scheme iVidiBlocks \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

A reformulação de 2026-11-20 substitui o anterior jogo circular. As partidas e os recordes desse jogo permanecem nos ficheiros antigos; as regras clássicas usam `classic-saved-run.json` e `classic-stats.json` para não misturar resultados incompatíveis. Não é uma reprodução exata de uma edição comercial específica.

Desenvolvido por David Arsénio Martins · [ividi.dev](https://ividi.dev) · [MIT](LICENSE)
