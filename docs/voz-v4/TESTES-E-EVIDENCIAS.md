# Testes e evidências — Voz V4

## Ambiente e fronteiras

Windows, Node 24.19.0, Vitest 3.0.5 e Edge headless no laboratório local. Ruby/Bundler não instalados localmente; Docker Desktop sem daemon Linux utilizável. Rails/PostgreSQL/Redis foram executados na CI GitHub, com banco descartável dedicado, localhost e Redis DB 15. Nenhum teste usou credenciais produtivas ou fez ligação/envio real.

O laboratório usa **componentes reais** GlobalVoiceBar/Hoya/InboxVoicePanel/OutboundVoiceDialog, store/router/i18n e adaptadores sintéticos de SIP/API. As rotas placeholder servem somente à montagem isolada, não provam navegação integral da aplicação. Bloqueio de rede permite apenas `127.0.0.1:5226`. Capturas têm banner de laboratório e dados sintéticos.

## Histórico RED/GREEN

| Execução | Resultado | Limite |
|---|---|---|
| Rails RED `2af5a6fc`, run 42626777472 | 98 exemplos / 7 falhas | Contexto/filtro não implementados e uma preparação de estado do fixture corrigida |
| Pausa RED `0cd08cb8`, run 42629305380 | 100 exemplos / 2 falhas | Availability permanecia online após pausa |
| CI `f02031cda3c662fd645af9b2560c10e5a8167433`, run 42634218497 | **100 RSpec, 358 Vitest/39 arquivos, lint 0 erros, build aprovado** | Prova dessa revisão, não aprovação automática de mudanças posteriores |
| Histórico RED `9b256529`, run 42637693973 | 104 exemplos / 3 falhas | Histórico ausente, retry alterando versão e nota em projeção view-only |
| Persistência `bf65be33`, run 42639530689 | 106 exemplos / 0 falhas | Run falhou posteriormente em lint Ruby; refatorado sem disables |
| Candidata `e8f23155`, run 42640061117 | **106 RSpec, 366 Vitest/41 arquivos, RuboCop 7 arquivos/0 infrações, JS lint e Vite build aprovados** | E2E falhou no loader TypeScript por `import.meta` em config CJS; corrigido para path.resolve(__dirname), novamente executado localmente |
| CallWorkspace/contexto local | 27 testes: RED 4 falhas → GREEN 27/27 | Adaptadores de telefonia sintéticos |
| Cabeçalho duplicado | 24 testes: RED 1 → GREEN 24/24 | Inclui caixa WhatsApp previamente selecionada |
| Histórico de notas e painel | GREEN 56/56 | Escape de HTML, cursor, erro de rede, identidade estrangeira e permissão |
| Rascunho tardio | RED 1 → GREEN 33/33 | Sem remount e sem sobrescrever edição local |
| Revisão independente | RED 2 → GREEN 35/35 | Popup busy não fecha e hangup continua durante hold pendente |
| E2E local final ampliado | **18/18, 0 skips, 0 flaky** | Seis resoluções, SIP/API sintéticos; não prova áudio/PABX |
| Broker branding local | **32/32** | Interpolação Compose, imagens pinadas e workflow de engine; não é teste de novo pareamento |
| Broker CI `d1ae956...`, run 42632287978 | **SUCCESS** | Workflow preserva exclusão das rotinas de backup/recuperação fora do escopo |

As contagens de execuções sobrepostas não devem ser somadas como testes distintos. O manifesto final no pacote de entrega deve registrar o HEAD/run mais recente, inclusive a regressão de schema e o E2E em CI. Links de execução: [Voz](https://github.com/ClaudioHideki/jrc-conversas-lab2/actions/workflows/voice-v4-candidate.yml), [Broker aprovado](https://github.com/ClaudioHideki/BrokerJRCIA/actions/runs/42632287978).

## Comandos reproduzíveis sem telefonia real

```sh
node node_modules/vitest/vitest.mjs run app/javascript/dashboard/routes/dashboard/webphone app/javascript/dashboard/routes/dashboard/inbox app/javascript/dashboard/routes/dashboard/jrcContactCenter app/javascript/dashboard/components-next/layout/specs app/javascript/dashboard/__tests__/voiceV4Locale.spec.js --maxWorkers=1 --minWorkers=1 --no-file-parallelism
node tests/playwright/node_modules/@playwright/test/cli.js test --config tests/playwright/voice-v4.config.ts
```

No Windows local, `JRC_VOICE_E2E_CHANNEL=msedge`; CI instala Chromium. Resoluções: 1920×1080, 1440×900, 1366×768, 768×1024, 390×844 e 320×800. Capturas: ligada, DTMF, espera enquanto WhatsApp B está selecionado, popup, chamando, recebendo e pós-atendimento. Nenhuma captura comprova transporte de áudio.

Rails na CI: suites `spec/{services,models,requests/api/v1/accounts,jobs}/jrc_contact_center`. Teste de writer força falha de revisão e comprova rollback da nota. Migration de observações passa down/up apenas no banco descartável. Schema reconciliado seletivamente a partir do arquivo gerado no PostgreSQL da CI: nota nova e estruturas/guards de mídia das migrations **já existentes** 20261102203000–205000. Não substituir schema antigo/novo indiscriminadamente.

Para conferir preservação dos guards sem disparar rotinas de recuperação, a CI executa somente dois exemplos do spec de mídia: `reserves an immutable new storage key` e `rejects a reserved SQL row`. Os outros exemplos desse arquivo não são selecionados.

## Lint e build

Comparação local dos 31 fontes JS/Vue alterados: baseline **0 erros/21 avisos**, candidata **0 erros/34 avisos**. Os avisos adicionais estão registrados por arquivo/regra em `lint-baseline-comparison.json`; incluem root v-if, chaves i18n dinâmicas e formatação Vue. Não foram suprimidas regras. Build completo é `bundle exec vite build` na CI; não foi declarado build Rails local. Não há typecheck TypeScript integral independente configurado/executado para o aplicativo Vue JavaScript nesta entrega.

## Incidentes e limites de prova

- A gravação por conector GitHub retornou 403; push da branch autorizada funcionou pelo Git e gerenciador de credenciais existente, sem extrair tokens. Acesso de leitura ao GitHub foi verificado.
- O provisionamento local do sandbox passou a falhar com `.sandbox-bin` acesso negado. Comandos locais de teste/leitura seguiram sob a revisão de aprovação, sem mudar alvos de produção.
- Uma execução local geral do Broker incluiu por engano suites de recuperação fora do escopo; foi interrompida. Não é contada como suite aprovada. Nenhuma rotina de backup/dump/restore foi executada no servidor. A CI Broker mantém essas suites excluídas por configuração existente.
- Fotografias anteriores de erros de campanha não foram reprocessadas. Não houve replay, envio ou teste de número real nesta entrega.
- Sem prova real de áudio bidirecional, mute/hold/transferência/DTMF, duas abas, reconnect do PABX ou correspondência do Call-ID. Esses aceites seguem pendentes.
- Produção não foi modificada; não há merge, deploy, mudança de ramal, trunk, gravação ou sessão WhatsApp a contabilizar nesta execução.
