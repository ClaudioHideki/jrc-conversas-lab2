# Visualização responsiva das mensagens — 18/11/2026

Produto: `f494fd38dd62929303279d39b4591372ac72e607`.
Branch: `codex/inbox-responsive-20261118`.
Base Git: `e6bd4cc9418b3522378a460bb97814b700f39123`, que preserva o produto
`d3d6623254c48fc379fb9d54c14226a2e1e9c223` observado no HTML público do ambiente.
O incremento preserva as correções anteriores de encerramento, projetos,
mensagens e os gates já integrados na main.

## Resultado

- Área de leitura priorizada conforme a largura e altura efetivas do atendimento.
  O painel do cliente abre no popup existente quando não há largura suficiente.
- Cabeçalhos, faixas de origem e espaçamentos compactos em áreas baixas, com o
  tamanho das letras preservado.
- Editor inicialmente menor em áreas baixas, com limites recalculados ao mudar a
  altura e ao variar o espaço dos controles. Arrastar, ampliar e restaurar continuam
  disponíveis. A lista de mensagens pode encolher e rolar dentro da cadeia flex.
- Ampliar conversa recolhe colunas e abas auxiliares. O nome e as origens de
  recebimento/resposta permanecem visíveis. Cliente e lista abrem temporariamente;
  Restaurar painel devolve o layout. O editor permanece montado e mantém o rascunho.

Decisão e critérios: [ADR0007](../adr/0007-visualizacao-responsiva-da-conversa.md).

## Ensaio visual

Chrome local, componentes nativos de layout compilados, mensagens e controles de
envio sintéticos. As dimensões abaixo são da janela CSS, sem dados reais de clientes.

| Janela | Altura anterior das mensagens | Altura nova | Modo ampliado |
| --- | ---: | ---: | ---: |
| 1280x625 | 28 px | 158 px | 200 px |
| 1366x768 | 169 px | 285 px | 334 px |
| 1920x1080 | 481 px | 481 px | 554 px |
| 1024x600 | 28 px | 133 px | 182 px |

Sem erros de navegador ou rolagem horizontal. Verificados rascunho ao
ampliar/restaurar, popup do cliente com Escape, lista recolhida, ampliação manual
do editor e redução de viewport. Em 1920x1080, o layout normal preservou a área
de leitura e as três colunas. Os resultados não garantem medidas idênticas em
todos os monitores, escalas do Windows, zooms ou conteúdos.

## Imagem e evidências

```text
ghcr.io/claudiohideki/jrc-conversas-lab2:sha-f494fd38dd62929303279d39b4591372ac72e607
```

```text
ghcr.io/claudiohideki/jrc-conversas-lab2@sha256:e1502e545cb9b4dc6c96eab2fd9068c5052ccc8fe0c02960b50ae7d3d3fb61dc
```

- Local: 200 testes existentes em 20 arquivos aprovados; ESLint dos componentes
  alterados sem erros, com quatro avisos preexistentes. Compilação do laboratório
  e ensaio visual acima aprovados.
- [Build e publicação 44363528959](https://github.com/ClaudioHideki/jrc-conversas-lab2/actions/runs/44363528959):
  três jobs aprovados, regressão adicional com 168 exemplos Rails e 77 testes Vue,
  gates puros preservados, 296 arquivos/2759 testes frontend,
  construção real, conteúdo/revisão/plataforma conferidos e smokes de aplicação e
  worker antes/depois da publicação por digest aprovados.
- Digest, plataforma linux/amd64 e label da revisão exata conferidos
  independentemente no GHCR por inspeção de metadados, sem baixar camadas no desktop.

As suítes se sobrepõem e não devem ser somadas como um total único.
O commit posterior de evidências altera documentação; a imagem corresponde ao
SHA do produto indicado acima.

## Aplicação e limites

No Dokploy, substituir a referência `image:` da base compartilhada do Compose
pelo digest acima, salvar e implantar. Aplicação e worker devem usar a mesma
versão. Aguardar a conclusão e atualizar a interface com `Ctrl+Shift+R`.
O operador pode usar Ampliar conversa e Restaurar painel conforme a necessidade.

Sem migration nova, mudança de permissões, envio real, backup, dump, restore,
merge em main ou implantação em produção neste incremento. A imagem publicada
e o aceite operacional no monitor do usuário são etapas distintas.

A primeira execução 44361164573 parou no download de pacotes do runner. A revisão
final reconhece também os espelhos regionais oficiais do Ubuntu; a execução
44363528959 concluiu a instalação com os mesmos pacotes, assinaturas e limite
de tempo. Nenhuma etapa de teste foi removida.
