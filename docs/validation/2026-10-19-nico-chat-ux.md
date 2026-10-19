# NICO: conversa privada simplificada

Implementacao local na branch `codex/nico-chat-ux-20261019`, baseada em `4633cc5c09c20d44694a95155375b208efbff69f`. Este documento nao comprova publicacao de imagem nem deploy.

## Comportamento

- Quick e painel completo usam o mesmo historico de conversa. Respostas informativas nao produzem mais banners de sucesso, contadores de acoes vazios ou resumo de workflow redundante.
- A cota de tokens sai do chat do operador. Os controles de consumo no backend e na administracao continuam existentes.
- Contexto, sugestoes, conhecimento e delegacao ficam em Mais opcoes. Abrir conhecimento ou preparar delegacao move foco e rolagem para os controles, inclusive em conversas longas; abrir nao executa delegacao.
- O compositor distingue ditar uma mensagem, conversar por voz, ouvir respostas, interromper leitura e encerrar. Ajuda longa aparece somente em Opcoes de voz. Revisao da transcricao, erros e prioridade de chamadas permanecem visiveis quando relevantes.
- Acoes continuam exigindo a previa e confirmacao previstas no protocolo existente. Respostas e recibos de comandos Broker continuam usando a fonte autoritativa. Nao houve mudanca de permissao, escopo de conta, regras de tomada de atendimento ou ativacao de bots.
- As instrucoes do runtime explicam voz privada com o NICO sem confundir com telefonar para clientes. Isso altera o runtime e requer sua propria nova imagem para entregar essa correcao de orientacao.

## Evidencia local

| Verificacao | Resultado |
| --- | --- |
| Regressao ampliada NICO, relacionamento, clientes e telefonia | 405 testes / 45 arquivos aprovados |
| Regressao final apos correcao de foco: NICO, Flow e componentes Broker | 142 testes / 20 arquivos aprovados |
| Runtime NICO, comando oficial serial `npm test` em Node 24 | 39 testes aprovados |
| Runtime `npm run typecheck` e `npm run build` | Aprovados |
| Contratos locais de manifesto e observador | 12 testes aprovados |
| ESLint dos oito arquivos Vue/JS alterados | 0 erros; 24 avisos de regras de estilo/i18n |
| Chromium: Quick e painel completo, larguras 390 e 1280 | 4 jornadas aprovadas; 0 erros JS e 0 requisicoes externas |
| Build Vite dos componentes reais com dependencias de integracao simuladas | Aprovado; 50 modulos |

Os testes novos falharam antes das correcoes de layout, orientacao de voz, reset de conta e foco de formularios. A revisao de codigo identificou o problema de foco em conhecimento/delegacao; os dois casos de regressao foram acrescentados e aprovados apos a correcao.

O primeiro teste do runtime, paralelo e dentro do executor restrito, teve tres falhas de inicializacao PGlite/WASM. O comando oficial serial, executado fora dessa restricao, aprovou os 39 casos. Nenhuma mudanca do motor foi feita para contornar esses testes.

As jornadas Chromium usam os componentes modificados, dados sinteticos e uma API simulada que recusa executar comandos. Conferem historico, ausencia de banners redundantes, ajuda recolhida, teclado, estado do alto-falante, previa de acao, confirmacao preservada e encaixe no viewport. Nao acionam microfone real, provedor, WhatsApp nem contas de producao.

O manifesto de composicao foi regenerado para 180 artefatos e conferido contra os arquivos finais. O hash dos guards de ownership permaneceu `da231b9ca8c44b56234f106aee2e8d5acd34caf41fa63787d5a69655db81a3f0`; isso comprova integridade local, nao instalacao do observador no servidor.

## Publicacao e limites

Nao ha migration nova, alteracao de Compose/ENV de producao ou mudanca no Broker nesta entrega de UX. A imagem JRC de producao `4633cc5c` nao inclui este trabalho local. Uma futura publicacao deve gerar imagens separadas do app JRC e do NICO runtime. Nao publicar apenas o app e afirmar que a orientacao do runtime ja foi atualizada.

Nao foi realizado build Docker completo: o daemon local estava indisponivel. O navegador autenticado do Codex tambem falhou antes de iniciar; nenhuma tela de producao foi homologada por este trabalho. Qualidade de voz, respostas reais do modelo, latencia, permissoes por usuario e operacao na stack implantada ainda exigem homologacao real.

## Modulos desativados na producao

Em 19/10, um GET publico ao HTML do JRC confirmou `jrcFlowsEnabled=false` e `jrcBrokerEnabled=false`. O frontend combina essas flags globais com as features da conta. Assim, as features verdes do Super Admin coexistem com os cards desativados.

A correcao operacional exige inventariar os fluxos por status e a integracao por conta antes de alterar flags. `JRC_FLOWS_ENABLED=true` pode liberar fluxos locais ja ativos, contrariando a orientacao atual de nao ativar bots. `JRC_BROKER_ENABLED=true` exige previamente chave de credenciais valida e origem autorizada; ativar uma feature nao substitui cadastro nativo, permissoes ou prova de ownership. Nenhuma flag foi alterada.
