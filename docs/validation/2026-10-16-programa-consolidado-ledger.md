# Programa consolidado: registro verificável

## Estado corrente — fechamento local de 19/10 (prevalece sobre o histórico abaixo)

Desenvolvimento do corte suportado concluído localmente. Integração na main e imagens autorizadas após os gates; deploy automático Broker confirmado desligado pelo usuário. Nenhuma alteração no servidor ou ativação de bot.

- Importação Broker commit `b37bc42`: snapshot congelado, checkpoint, worker e bootstrap silencioso. Somente texto individual em cache após prova de identidade; sem histórico integral do telefone, grupos ou anexos.
- Domínio Broker commit `42848bf68f9c07fdc6e102de37ccb4a845e463db`: lead/tarefa/reunião, recibo causal e recuperação por GET. Cobertura corporativa e responsável revalidados. Central sem a migration não anuncia nem executa o comando novo; protocolo antigo preservado. Não constitui barramento global de eventos nem convite externo.
- Carteira: revisão congelada de1–50 clientes, cadência versionada, recibos nativos e parada por resposta/humano/cancelamento. Sem campanha pública.
- NICO: orçamento/reservas,12 passos, conhecimento aprovado e revogável; voz interna opt-in5min/12turnos. Novidades no host Rails/Vue; runtime separado preservado.
- Broker geral:421 arquivos/3221 testes PASS, typecheck PASS, bundle11 arquivos/zero achados, auditoria zero vulnerabilidades e submódulo Evolution preservado. Domínio:10 PostgreSQL focais PASS.
- Rails: 343 exemplos distintos selecionados PASS/zero pending, agregados por arquivo usando a rodada final de cada conjunto. Inclui13 domínio,10 cobertura corporativa, upgrade e os21 de concorrência inicialmente protegidos pelo nome do banco. Guardas reconhecem apenas o banco descartável autorizado. Limpeza usa tabelas explícitas/IDs monotônicos, sem CASCADE, aumento de timeout ou remoção de asserções. Os21 passaram em PostgreSQL temporário em memória com esquema idêntico; container removido. Isto não prova durabilidade sob falta de energia.
- Interface: NICO96, carteira/cadência25; editor nativo7 jornadas locais/zero requisições externas, gerado do commit Broker42848bf com201 entradas e scanner sem achados. Build JRC5439 módulos PASS em25m04; avisos existentes de chunks, Browserslist e asset de marca permanecem. Lint NICO0 erros/16 avisos; domínio Ruby6 arquivos sem offenses.
- Fontes e manifestos finais conferidos após as correções; resultados detalhados locais em `.sessions/consolidated-final-native-evidence.json`. CI remoto, imagens/digests e homologação operacional ainda exigem suas próprias evidências.

Os itens abaixo registram o histórico e limites anteriores. A conclusão local acima substitui pendências de implementação já cobertas; homologação real externa, Meta/chamadas, infraestrutura/carga de10mil conexões e cobertura fora do contrato continuam separadas.

## Incrementos deste desenvolvimento

| Componente | Commit local | Resultado |
|---|---|---|
| Broker: handoff cooperativo | eb933b4 | Aceita política de time conhecida true/false e verifica agente efetivo no time/caixa; mantém humano |
| Broker: troca concorrente de agente | 8277b45 | Confirmação vinculada ao alvo validado; mudança durante consulta fica UNKNOWN sem repetir POST |
| Broker: ciclos físicos Chatwoot | 8527aed | Novo atendimento mantém mapa/recibos antigos; intervenção humana histórica pausa corrente na admissão; envio concorrente e autoridade automatizada protegidos |
| Broker: switch tipado | 51dbab1 | Decisão escalar estrita com casos estáveis/default, mesmo catálogo, motor, simulação e canvas |
| JRC: Customer360 | 86f08ce4 | Mapa sob demanda de relações autorizadas, contagem distinta/amostra10 e acesso às abas existentes |
| NICO: caixa Broker legada | 9ff3354b | Requer adoção verificada antes de envio público; preserva notas e aprovação coordenada |
| NICO: radar e filtro de leitura | 56f13dfd | Backlog completo, categorias determinísticas, histórico independente de Relacionamento e custom roles de administradores aplicados |

O incremento anterior de análise rastreável 8859f585 já estava publicado antes da orientação de aguardar o corte completo. Nenhum dos commits acima foi enviado nesta etapa.

## Evidência e limites

- Broker: handoff33 testes de integração. Ciclos18, histórico10, interface41 e QR unitário17 aprovados; typecheck aprovado. Suíte geral dos ciclos: 408 arquivos/3125 testes aprovados em331,05s, antes do último ajuste focal do histórico (que recebeu os dez testes PostgreSQL/17 unitários próprios). Regressões adicionais registradas no documento focal do Broker. Nenhuma alteração do gerador de segurança ou de seu timeout.
- JRC: 15 exemplos Rails Customer360, oito de interface. Radar/filtro/domínio: 43 exemplos aprovados. Bindings NICO20 e OperatorSession20 aprovados em rodadas focais. Commit gate: 18 exemplos de concorrência aprovados sem pending em PostgreSQL descartável.
- Revisões independentes produziram regressões reais de concorrência, autorização e histórico; achados Important foram corrigidos com RED/GREEN. Não equivalem a homologação real de WhatsApp/Meta/chamadas.
- Manifestações de composição/ownership JRC regeneradas e verificadas para os fontes candidatos. Broker acrescenta migration0066 somente para índice e probe correspondente; não foi aplicada ao servidor. Compose, ENV e digests de produção permanecem sem alteração nesta etapa. Nenhuma migration JRC nova.
- Editor embutido JRC regenerado a partir do fonte commitado51dbab1 (198 inputs; scanner sem achados). Teste real de navegador exclusivamente local:7 cenários aprovados, incluindo switch, CSS isolado e restrição de publicação; zero requisições externas. Fontes, manifestos e artefatos ficam na candidata separada, sem atualizar servidor. O formato do switch legado do JRC não foi convertido nem alterado.

## Ainda não concluído

1. Ciclos remotos QR/Chatwoot: correção implementada/verificada localmente no commit8527aed; falta sua homologação real no ambiente separado. Migração0066 deve acompanhar a imagem futura. Não substituir vínculos manualmente nem ativar bot no servidor atual.
2. Importação histórica: completar cursor/checkpoint estável e provar cobertura sem perda/repetição sob novas mensagens; disponibilidade do catálogo/grupos não comprova importação integral do WhatsApp.
3. Público em lote, recorrência e cadência: ainda precisam de inscrição versionada, prévia congelada, recibo por item e cancelamento por resposta/intervenção humana.
4. Jornadas guiadas e nós adicionais: switch tipado implementado no Broker e pacote de editor candidato JRC; falta homologação no servidor. Comandos de domínio/eventos no Flow, integrações de escrita autorizadas, agente limitado e conhecimento por empresa continuam pendentes. Nós existentes não foram declarados universalmente funcionais.
5. Agendamento de serviços e voz contínua/transporte de chamadas: não foram implementados neste corte. Ditado/leitura existentes e PABX não comprovam atendimento IA em ligação WhatsApp.
6. Fechamento consolidado: verificar todos os adaptadores/contratos, build, CI remoto e imagens somente após concluir as entregas. Homologação em servidor separado depende de configuração dos tenants A/B, Chatwoot externo e ativos Meta/chamadas. Capacidade de 10 mil conexões exige carga real e dimensionamento; não é garantida por testes locais.

Fontes de planejamento: `docs/superpowers/specs/2026-10-16-nico-jornada-candidata-design.md` e relatórios públicos da comparação Astra em `entregas/2026-10-16-videos-astra-comparacao-jrc.json` no workspace principal. Não houve cópia de código privado do concorrente nem engenharia de um serviço sem acesso autorizado.

## Auditoria de publicação — 19/10/2026

O usuário autorizou integrar na main depois da aprovação dos testes. **Publicação ainda não aprovada**: escopo incompleto e regressão integral sem conclusão. Nenhum push, imagem, deploy, alteração de ENV ou ativação de bot ocorreu nesta auditoria.

Verificação direta no Dokploy: Rails Grupo JRC executa `/app/.git_sha` igual a `98a4be7714be41d33bf9ff52b254ebb773864769`, a base preservada pela candidata. NICO executa `557efc21b2f59b7539bf49eb04607642442345a6`; os fontes `services/nico-runtime` e seu Dockerfile não diferem desse commit na candidata. As melhorias recentes do NICO estão no host Rails. Broker respondeu HTTP 200/ready e baseline `0065_qr_identity_pending`; a árvore local atual exige `0067_history_import_ledger`.

O remoto JRC não possui `refs/heads/main` nesta consulta. Seu HEAD padrão é `codex/cadastro-mestre-20261002` em `128243d9`, ancestral da base de produção. Não tratá-lo como a imagem instalada nem substituir a base recente do outro desenvolvedor. Broker remoto main está em `1560c181`.

Resultados novos: NICO runtime 38 testes e build aprovados após instalar as dependências do lockfile; JRC UI 100 testes aprovados (55 dos módulos + 45 Quick NICO/Inbox); Broker 67 focais e 80 PostgreSQL aprovados, TypeScript/build/scanner público aprovados. Editor compartilhado: sete cenários reais de navegador local aprovados, zero requisições externas. Manifestos de composição/ownership verificados.

A primeira rodada geral Broker teve falhas/timeouts sob pressão de memória; a repetição com dois workers também não concluiu e foi encerrada, sem declarar aprovação. Docker local não respondeu ao comando de consulta com timeout de 15 segundos. Rails completo, imagem JRC, E2E completo e upgrade/rollback operacional continuam sem aprovação nova. Nenhuma asserção foi removida nem timeout aumentado.

Há desenvolvimento Broker adicional ainda sem commit: contrato/store/writer e migration 0067 de histórico, painel e testes. O painel está montado em ChannelDetail, mas suas rotas `/v1/channels/:id/history-import` não estão registradas na API; o host/worker/fonte real ainda faltam. Portanto o histórico completo não é uma funcionalidade concluída, apesar dos testes do core aprovados. Permanecem os demais critérios pendentes de cadências, comandos/eventos, conhecimento/agente e voz do plano.

Relatório estruturado desta rodada no workspace principal: `entregas/2026-10-19-regressao-pre-publicacao.json`, com fontes, produção observada, logs, limites e condições para a próxima publicação.

## Continuação 2026-10-19 — evidência atualizada (substitui os estados anteriores)

Broker: build completo aprovado; suíte geral 419 arquivos/3209 testes; integração focal PostgreSQL 10 arquivos/113 testes; E2E local 8 cenários desktop/mobile; bundle11 arquivos sem achados; OpenAPI regenerado; diff check aprovado. Logs `.sessions/history-consolidated-{build,general,integration,e2e}.log`. Esses resultados antecedem o ajuste adicional de fronteira da identidade, que recebe regressão própria antes do próximo gate.

As rotas de histórico, fonte congelada PostgreSQL, worker dedicado e interface já foram implementados na candidata Broker. A fonte v1 cobre texto individual armazenado no engine; grupos, anexos e dados ausentes no cache não estão cobertos. O espelhamento silencioso exige o adaptador `jrc-history-import/1` da candidata JRC; não injeta mensagens antigas pelo endpoint normal.

JRC: adaptador histórico e lote revisado passaram juntos em20 exemplos Rails (`/tmp/history-batch-final.log` no runner descartável). Incluem autorização atual, dados congelados, recibos, cancelamento parcial, falha injetada com rollback e revogação no worker. A falha de retry ilimitado de unicidade foi reproduzida e corrigida com serialização por request; nenhuma falha arbitrária é repetida. Interface/cadência e concorrência seguem em fechamento. Migration candidata nova20261019120000; não aplicada ao servidor.

Ruling: o logout da Evolution mantém o cache Message (monitor.service.ts cleaningUp), enquanto a limpeza completa só ocorre em cleaningStoreData. Por isso, um owner atual não certifica mensagens anteriores à observação verificada. O histórico deve expor/validar a fronteira temporal de identidade, sem fingir importação integral de todo o telefone. Custo: registros anteriores dependem de outra fonte com prova de ownership; não há fallback que os importe como live.

Nenhuma imagem gerada, push/merge, bot ativado, mensagem real ou alteração no servidor nesta continuação. Os critérios restantes do programa (cadências, comandos/eventos de domínio, agente/conhecimento, voz e homologação externa/capacidade) continuam pendentes até sua implementação/prova; não são aprovados por esta suíte focal.

2026-10-19 latest: Broker identity guard RED/GREEN completed. Build+OpenAPI PASS; TypeScript PASS; general419files/3210tests PASS in869.60s; post-boundary PostgreSQL source/application17PASS and UI/compose23PASS; bundle11/findings[] PASS. JRC historical+reviewed batch+cadence+independent-connection concurrency33Rails PASS (zero pending) and Vue4files25tests PASS. These remain local synthetic evidence. No publication, merge or production changes. Native cadence supports no public sends and respects reply/human/cancel/customer changes; following components6–8 remain incomplete.

## Review correction pass — current evidence

The focal review found three real defects; publication remained rejected. RED tests
reproduced ordinary historical bootstrap, a concurrent inbox-grant deletion and a
conditional playbook falsely reported applied. Corrections: callback-free scoped
bootstrap with deterministic identity; native InboxMember/ServiceDesk/Project grant
locks through commit; receipts verified against actual native playbook resources.
A current-agent two-connection test now proves the inbox grant fence.

Post-correction regression37Rails PASS (`/tmp/history-review-consolidated.log`),
plus PostgreSQL migration reversal/reapply1PASS (`/tmp/reviewed-migration-drill.log`)
in the explicit disposable database, preserving native conversation/account data.
Broker adapter9PG tests and client4unit PASS. Full JRC Vite build PASS with Dockerfile's
existing 4GiB heap options; the initial default-heap build OOM was not a successful
build. Composition input now includes157 artifact files; manifests generated/verified
and18 operational Node gates PASS. New generalized Broker suite still running.

Component6 focal plan: `docs/superpowers/plans/2026-10-19-domain-commands.md`.
Commands/events, bounded knowledge/agent acceptance and voice remain unfinished;
no image/merge/push/server change or real bot/cadence/message has been activated.
