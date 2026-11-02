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

Exigir CI exata do candidato, schema estrutural consistente e imagem oficial antes de merge/release. Fechar teste HTTPS com Broker e Sidekiq reais (probe atual ainda porta sintetica), dois consumidores isolados, custodia integral e recuperacao da engine. Captura Evolution seguefalse/UNPROVEN; imagem API/web nao atualiza engine.

WA permanece parcial em historico completo de conexoes, calendario/fallback e metricas; Flow continua por fases; Central multidominio/NICOgates/adapters e carga final nao estao encerrados. CCLX real, fontes externas e piloto50numeros/30dias aguardam contexto/autorizacao especificos. Capacidade900 nao medida. Publicar componentes independentes aprovados com limites explicitos; nao declarar100%.
