# Publicação autorizada — Grupo JRC — 05/11/2026

O usuário autorizou gerar a imagem e implantar no Grupo JRC. A inspeção do Dokploy e de `/app/.git_sha` confirmou fonte `200b4f1ddd7459ec924e314cfe34cb93f11c5d5e` e imagem `ghcr.io/claudiohideki/jrc-conversas-lab2@sha256:6b6e364af77dfbd7267afbdd5dc4b9a3ff1783208352da76e502931101dbb942`. Essa fonte e a main `a92f9bf8dd4a0b8828530f6c5d52d367449fe24b` estão preservadas na candidata. Sem migrations novas desde a imagem instalada. Não alterar ENV, engine Broker, sessões, campanhas ou regras reais das caixas nesta publicação.

Incrementos executáveis: agrupamento por caixa `5dcf046b`, distribuição exclusiva `4724688e`, escalas e pausas `26a8cd87`. O incremento de publicação amplia a CI WhatsApp para permissões, notificações, tempo real, filas e escalas, e adiciona jornada de navegador desktop/mobile com supervisor, capacidade e períodos individuais persistidos na fixture isolada. Os testes de interface não equivalem a homologação de WhatsApp real. Publicar somente depois da CI nativa e da CI WhatsApp no SHA candidato; o build GHCR deve consumir o run nativo desse mesmo SHA. Registrar digest e pós-deploy separadamente antes de afirmar implantação concluída. Não usar as evidências antigas abaixo como confirmação do release novo.

# Candidata local — escalas individuais e pausas — 05/11/2026

Continuação de 4724688e na branch codex/shared-inbox-history-20261104. Leia `../atendimento/VALIDACAO-PAUSAS-ESCALAS-20261105.md` e o plano agent-shifts-pauses de 05/11. Escala semanal por agente/caixa, almoço programado, noite, revalidação de horário antes da atribuição e retomada ao reabilitar distribuição foram implementados. Sem migration nova, produção, push, merge, imagem ou deploy. Gates locais: Rails308/308, revalidação focada107/107, Vitest227/227 e nova revisão focada44/44; ESLint0erros/22avisos, RubyLint9arquivos/0ofensas. Build/CI e navegador permanecem pendentes. Os limites estão no relatório; checkpoints abaixo são históricos.
# Candidata local — distribuição central — 05/11/2026

Branch `codex/shared-inbox-history-20261104`, base `5dcf046b63eb79740b30d76893828f4cbed52280`. Leia `../atendimento/DISTRIBUICAO-CENTRAL-20261105.md` e o plano de 05/11. Exclusividade por caixa, supervisores, capacidade proporcional, FIFO, reabertura, guards da URA nativa e revogação de caches implementados. Testes locais: 285 RSpec e 219 Vitest, sem falhas, com concorrência PostgreSQL/Redis habilitada. Build frontend completo pendente por OOM; lint completo tem débito de métricas/estilo. Sem migration nova, push, merge, imagem, deploy ou ativação produtiva. Broker não alterado; handoff remoto e histórico completo continuam com gates próprios. Não tratar os checkpoints históricos abaixo como estado produtivo revalidado hoje.
# Checkpoint ativo — 03/11/2026

PUBLICAÇÃO CONCLUÍDA: leia `PUBLICACAO-GRUPO-JRC-20261103.md`. Fonte executáveledd6f1a2570676a64d0e9086652c8e1da476c7ac; CInativa41645392552eimagem41645896885SUCCESS. Digestdabbbfcad2a97c659fb90c269b3e96a7f7c619fe70d8d56800486023c9ce4a76 implantado no Grupo JRC. Railsbc16920b5640eSidekiq50b51ecfc39b no mesmo SHA, heartbeat ativo,7migrations aplicadas/0pendentes, HTTPShealth200. O registro documental posterior não é outra candidata executável. Não repetir o deploy sem necessidade; não confundir este release com homologação real de campanha, IA paga, CCLX ou capacidade.

Atualização de escopo neste dia: o usuário autorizou publicar a candidata LAB2 consolidada e atualizar o Grupo JRC. Leia `CANDIDATA-CONSOLIDADA-20261103.md` e o plano de release de03/11. Brokerd1d0f2e já publicado/implantado; não repetir seu deploy. LAB2 permanece em validação antes da promoção; banco frio e MinIO4/4 passaram, UI134/134. Registrar CI/imagem/deploy como níveis separados.

Branch atual codex/lab2-integral-20261102; preservar WIP e base20e56104. Leia MIDIA-HARDENING-20261103.md e MIG-INTEGRAL-LAB2-20261102.md. As instruções de release abaixo são históricas, não autorização para deploy agora. Editor do Broker ef5c5ae instalado; serviços de mídia65/65 e NICO60/60. Faltam MinIO do importador, schema frio, CI/build completos e revisão integral.

# Candidata integrada - 02/11/2026

Branch: `codex/release-integrada-specs-20261102`, PR3. Publicar pela branch efetiva `codex/crm-backoffice-servicedesk-visual-20261101`, observada novamente em50f7f07d802829dd44a67547fabad3aa77f3d196. Default antiga128243d nao e a release. Preservados merges19d28b72/57efc6e1, outbox89d87ccb e ajuste APT preexistenteab8f672b. O pedido vigente autoriza merge/imagens/Dokploy apos gates; backup/dump/restore, mensagens reais, pairing, replayUNKNOWN e carga historica indiscriminada continuam excluidos.

Broker relacionado: PR6 merge normal na main `ea7dc741d0c63792a969dddeac2bd35b6cbdf514`; CI pos-merge41489155114 SUCCESS. Imagens oficiais41493398462 publicadas com sucesso (APIae6229ed0d67cf2bd582291e4c6275dd641d57fbb75c88931fee14476cff6cd1 / web466c3d32aaa6729d8d2783bc9001a14ce9cf4cb728b8fd8c9caaf1623bef5546); manifestos confirmados no GHCR. Nao confundir com deploy. Editor compartilhado regenerado desse SHA:204 insumos commitados,0findings, JSsha256b377670478105932e312e28e64beb7ff5760832339483e5723377ff3c681f3b6.

## Incrementos implementados

- Outbox transacional mensagem/obrigacao, recovery por lease e callback estrito. Preserva identidade da campanha, adiamento sem gastar tentativa, UNKNOWN sem replay cego, exclusao de notas privadas/ecos e atualizacao terminal. Wrappers Survey/ServiceDesk nao produzem ACK falso quando recusam I/O ou suprimem erro.
- Conexoes autorizadas, novo numero e reconexao em modal contextual. Eventos de saude usam a mesma consulta limitada; confirmacao exige tentativa explicita + CONNECTED + READY + identidadeCONFIRMED. Nao equivale a entrega/sincronizacao de mensagens. Abas com teclado/foco, contexto e revogacao; titulo acessivel no dialog nativo.
- Distribuicao por conexao sobre o dispatcher existente: times ordenados, rodizio/prioridade/direto, presenca/pausa, capacidade agregada e concorrencia. Mantem inbox e conversas atribuidas; vigencia apenas apos salvar.
- Auditoria atomica antes/depois por inbox e por configuracao GLOBAL_ACCOUNT, inclusive sem inbox impactada. Usuario atual revalidado; System explicito. Historico imutavel pelo modelo e triggers SQL, preservando somente cascades/nullify dos FKs existentes. UI diferencia regra global, inclusao/desabilitacao, regra local e sistema.
- Reconciliacao DataImport somente leitura: totais desconhecidos, identidade entre runs, mappings ausentes/cross-account, tipos fora de escopo, midia nao verificada. Nao e Central completa nem prova de carga finalizada.
- Flow reutiliza editor/contratos do Broker; maximo opcional de tentativas de menu com saida de esgotamento e comportamento legado preservado. Nao introduz runtime concorrente nem encerra roadmap futuro.

## Testes e evidencias

90a8fcac teve267exemplos Rails e89UI locais aprovados. CI desse SHA executou580exemplos com14falhas de setup por FLOW_TEST_REDIS_URL ausente; corrigido env explicito no job, sem afrouxar assertions. Os14casos afetados passaram localmente antes da revisao de isolamento Redis. Fixtures antigas usavam FLUSHDB: substituicao por namespace real por exemplo e sentinelas estritas foi validada apos RED2/2: GREEN16/16, sem pending ou reset amplo. Lint dos2specs tem13offenses legados documentados (globais do adapter, assertions e helper antigo), sem disables.

WA003:96/96 em17arquivos apos RED de identidade/abas; depois apresentacao global64/64 nos3arquivos afetados. Dialog real teve RED isolado por falta de nome acessivel; GREEN final66/66 em4arquivos afetados, incluindo2casos do dialog real; lint0erros/3avisos dinamicos preexistentes. Nao usar stub como prova de focus trap/E2E de navegador.

WA010/CA11: REDglobal34exemplos/14falhas esperadas; GREENfinal65/65,0pending, incluindo concorrencia real2/2. Criacao fria do schema100000 + migration110000 final em banco sintetico novo; banco anterior preservado. SQLguard NULL-safe evita inbox nula tratada como pai removido. Historial de tentativas e falhas intermediarias preservado nos logs; nao somar suites sobrepostas.

Lint anterior:0erros/34warnings no recorte;2erros preexistentes AgentFlowsPage no-plusplus no conjunto amplo, comprovados em HEAD. Ruby Trigger/Controller mantem baseline documentado, sem disables. Novos arquivos devem manter lint proprio limpo. CI completa do novo SHA, build e gates da imagem continuam obrigatorios; CI antiga nao aprova novo candidato.

## Schema e compatibilidade

Migrations novas20261102090000(obrigacoes),20261102100000(auditoria) e20261102110000(guards e escopoGLOBAL_ACCOUNT). Nao editar as migrations historicas nem apagar ledger. Schema110000 reconciliado seletivamente a partir de catalogo sintetico:319tabelas/772FKs anteriores preservados,49linhas de diff; nao incorporar reescritas de casts fora do incremento.110000 permite inbox nula somente para eventoGLOBAL_ACCOUNT via CHECK; down recusa reduzir NOT NULL se houver auditoria global, para preservar dados. A contingencia e voltar apenas aplicacao compativel ou corrigir para frente, nunca apagar historico.

Broker0079 e requisito do core candidato; servidor observado ainda0078, ledger78/hash agregado confirmado. Fixture de upgrade0078para0079 passou: dados/pendencias/UNKNOWN/ledgerpreservados, HTTPdefault, idempotencia, oldbinaryincompativel. Nao usar provision que reseta credenciais. Nenhuma migration/deploy produtivo deste incremento confirmada neste checkpoint.

## Lacunas e proximo passo

Exigir CI exata do candidato, schema estrutural consistente e imagem oficial antes de merge/release. O teste adicional HTTPS com Broker e Sidekiq reais foi executado no incremento isolado descrito abaixo; revisar/publicar esse harness separadamente. Recuperacao da engine continua com gate proprio. Captura Evolution seguefalse/UNPROVEN; imagem API/web nao atualiza engine.

WA permanece parcial em historico completo de conexoes, calendario/fallback e metricas; Flow continua por fases; Central multidominio/NICOgates/adapters e carga final nao estao encerrados. CCLX real, fontes externas e piloto50numeros/30dias aguardam contexto/autorizacao especificos. Capacidade900 nao medida. Publicar componentes independentes aprovados com limites explicitos; nao declarar100%.

## Checkpoint isolado: custodia HTTPS real

Branch local `codex/lab2-https-custody-20261102`, baseada no merge PR3 `daae59ecdbfd28008773a8adf9ec13f34ac8f486`. Nao altera app/db/workflow nem a release do core. O incremento contem somente fixture opt-in e documentacao; requer revisao e publicacao proprias.

Gate observado `LAB2_TLS_BROKER_DURABLE_CUSTODY`, run `e4603a88-5311-42e9-b3d2-319cdeae8f5a`, launcher exit0. Dois consumidores LAB2 independentes em bancos novos, account/inbox/message reais1/1/1, Redis DB0/1. Rails7.1.5.2 + Sidekiq7.3.1 -> SafeFetch real -> TLS CA validada -> ingresso/servico/HMAC/migrations/RLS reais da imagem API EA. Cada org terminou com1observacao+1CHATWOOT_REPLY PENDING, cross-tenant0; A delivered/3, B delivered/2. Houve indisponibilidade real apos COMMIT do produtor, assinatura cruzada401, ACK retido apos COMMIT do receptor e SIGKILL137 do Sidekiq com recuperacao por lease. UUIDdelivery/bodyhash estaveis; o Broker deduplica pelas chaves reais de mensagem/destino, nao pelo header de delivery.

O stack completo passou antes dos ajustes finais de estilo Ruby. Depois passaram unidade9/19assertions/0falhas/0skips, RuboCop6arquivos/0ofensas, parsers Ruby6/JS3/PowerShell1 e3checks criptograficos. O stack NAO foi repetido depois; nao afirmar que o SHA final deste incremento recebeu o gate completo. O revisor deve avaliar esse limite ou pedir novo run quando houver slot autorizado.

Os seis containers da prova foram parados/exit0, sem portas publicadas, com volumes/DBs preservados e link de rede desconectado do Rails. CA privada/credenciais ficaram fora do Git; SSRF produtivo nao mudou. Sem worker fisico, numero/WhatsApp real, Chatwoot stock/CCLX, dois Chatwoots instalados, boot produtivo completo ou jornada bidirecional. Lease expirou controladamente, sem alegar decurso do TTL natural.

Veja [operacao e falhas de preparacao preservadas](../../spec/homologation/broker_https_README.md) e [evidencia sanitizada](evidence/broker-https-custody-20261102.json). Nao publicar logs brutos, manifestos privados, caminhos temporarios privados ou chaves.

## Checkpoint final da fixture HTTPS

O P2 de cleanup foi corrigido no commit local `f1ffd1b9de2bc773ad8c1983f25f1dd352579bb5`, separado de283378b1. Confere exitcodes/inventario/ownership/estado parado/desanexo e falha fechado se nao puder provar cleanup; nunca mascara erro primario do stack. Resultado e mensagem positiva so sao publicados depois de cleanup verificado. RED3pass/8fail e REDnullinventory14pass/1fail; GREEN15/15contratos WindowsPowerShell sem Docker/Pester.

A UMA rodada fria final autorizada passou: `bb759c3f-76e6-4f87-a9a8-d57d172276b3`, launcher exit0, fonte EXATA `f1ffd1b9de2bc773ad8c1983f25f1dd352579bb5`. Preflight Gitblobmatch13/13 e hashesLF; pos-run13/13hashes materializados Rails iguais. Inclui estilo Ruby final e cleanup corrigido. Cleanup Verified=true/Errors=[]/6Stopped=true/RailsDetached=true antes de criar result.json; inventario independente final6exited0/zeroportas. A delivered/3, B delivered/2;1observacao+1job PENDING por org/cross-tenant0. TLS3/3, assinatura cruzada401, ACK retido apos COMMIT, SIGKILL137, recovery e linhagem UUID/hash preservados.

Checks finais no mesmo conteudo:9unit/19assertions/0falhas/0skips;15cleanupcontracts/0falhas; RuboCop6arquivos/0ofensas; parsersRuby6/JS3/PowerShell3. [Evidencia final sanitizada com revisao/hashes](evidence/broker-https-custody-final-20261102.json). Este checkpoint/README/evidencia sao incremento posterior SOMENTE documental, com bytes executaveis comparados e inalterados contra f1ffd1b9. Nao atribuir a execucao ao SHA documental nem o run original e460 a283. O limite post-style anterior foi fechado pela nova rodada, sem reescrever os registros antigos.

Nada disso altera release/runtime/app/db/workflow. Sem worker fisico/numero/WhatsApp real, Chatwoot stock/CCLX ou boot completo produtivo. Seguem preservados DBs/volumes/failedruns, chaves privadas fora do Git/ZIP e SSRF produtivo inalterado. Sem push/PR ate revisao final do Ack.
