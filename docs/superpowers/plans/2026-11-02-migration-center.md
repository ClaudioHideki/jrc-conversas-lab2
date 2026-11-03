# Central de Migração — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Construir a Central de Migração com staging, prévia, execução explícita, rastreabilidade e reconciliação, começando pelos modelos reais de clientes e contatos.

**Architecture:** Módulo `JrcMigrations` separado dos importadores DataImports existentes. Lotes versionados registram insumos, mapeamento, decisão por registro, vínculo de origem e evidência de execução. Adapters específicos usam validações dos modelos do produto e escrita silenciosa; nenhuma automação externa é disparada. A aprovação funcional é separada da conclusão técnica do lote.

**Tech Stack:** Rails 7.1, PostgreSQL, Vue 3, RSpec e Vitest existentes.

**Spec:** `output/specs-20261102/doc3.txt` no workspace pai, parágrafos 1–555; complemento vigente exclui backup/dump/restore e não autoriza carga real, cutover ou desligamento de legado.

## Global Constraints

- Mesma conta/tenant em registros, destinos, responsáveis, empresas e relações.
- Preservar identificadores e datas originais; não deduzir valores desconhecidos.
- Não substituir DataImports Contacts/Intercom nem disparar seus callbacks.
- Nenhuma carga real, comunicação externa, dump, restore, cutover ou credencial nova.
- Não instalar dependências; testes Rails somente com slot coordenado e DB sintético LAB2.
- NICO somente consome registros migrados após reconciliação e aceite; staging nunca é fonte de inteligência.
- Aprovações operacionais e dados reais de fontes permanecem ações do usuário; não fabricar sua aprovação.

## Review Focus

- Preview obsoleto após edição nativa ou concorrência: rejeitar execução até nova prévia.
- Mesma origem/ID em delta com conteúdo divergente: não duplicar nem retroceder datas.
- Identidades ambíguas por documento/e-mail/telefone: revisão humana, sem merge automático.
- Relação entre tenants, empresa, agente ou pai: recusar antes da carga.
- Callback de criação/edição de Contact: provar ausência de emissão de eventos e chamadas externas.

## Incremento 1 — Pipeline e cadastro mestre

Arquivos: `db/migrate/20261102130000_create_jrc_migration_center.rb`, `app/models/jrc_migrations/{batch,item,mapping}.rb`, `app/services/jrc_migrations/{catalog,stage,preview,execute,reconciliation}.rb`, `app/services/jrc_migrations/adapters/{company,contact}.rb`; specs correspondentes.

- [x] Escrever RED de staging sem mutação de destino, normalização, chave de origem e tenant.
- [x] Implementar ingestão limitada de linhas com fonte identificada, versão de mapeamento, hashes e datas originais.
- [x] Escrever RED de prévia criar/atualizar/ignorar/rejeitar/revisar, incluindo conflito e relação cross-account.
- [x] Implementar adapters Company (companies existente) e Contact com validação real dos modelos.
- [x] Escrever RED de execução explícita/reprocessamento/delta/concorrência/preview obsoleto e silêncio de callbacks.
- [x] Implementar execução transacional por registro, correspondência única e proveniência estável.
- [x] Escrever RED de reconciliação: alvo apagado, alterado, relação quebrada, rejeitado e aceite negado.
- [x] Implementar reconciliação e aceite separado, sem considerar contagem isolada prova suficiente.

## Incremento 2 — Operação pelo produto

Arquivos: `app/controllers/api/v1/accounts/jrc_migration_batches_controller.rb`, `config/routes.rb`, `app/javascript/dashboard/api/jrcMigrations.js`, página própria sob configurações de dados e traduções en/pt_BR.

- [x] Escrever RED de autenticação/admin revalidado, escopo de lote e descarte de resposta antiga na UI.
- [x] Implementar upload JSON/CSV controlado, seleção de domínio, mapeamento e prévia visível.
- [x] Exigir ação explícita de executar; mostrar resultados, erros exportáveis, reprocessamento e reconciliação.
- [x] Expor somente recursos e adapters realmente disponíveis; não anunciar conectores não implementados.
- [ ] Integrar gate NICO nos consumidores reais do cadastro mestre e testar antes/depois do aceite.

## Incrementos posteriores do doc3

Expandir por dependências reais para usuários/equipes/RBAC, contratos/documentos/CRM, conversas/mensagens/anexos, Service Desk, projetos e demais domínios. Cada adapter exige seus próprios testes de relações, datas, RBAC, integridade e silêncio operacional. Inventário oficial, volumes, credenciais, amostras reais, aceite funcional, homologação externa, carga final, cutover e encerramento do legado não são substituídos por fixtures ou por este plano.

## Incremento 3 — Histórico, projetos e Service Desk

- [x] RED de histórico append-only por lote, referência malformada e calendário impossível.
- [x] Implementar eventos de lote com cursor, ator, data e guard SQL; validação estrita dos insumos.
- [x] RED de adapters reais Project/Task e implementar relações, datas, responsáveis e subtarefas.
- [x] Confirmar GREEN desses incrementos e RED de optimistic locking do editor nativo.
- [x] Corrigir lock_version e comprovar GREEN com proteção da atualização nativa.
- [x] Escrever seis casos Service Desk para contexto histórico, autoria, histórico imutável e SLA.
- [x] Observar RED Service Desk, implementar adapters específicos e comprovar ausência imediata de jobs/recálculo.
- [x] Implementar ingestão de anexos com bytes/hash/leitura e vínculos tipados, após RED próprio.

### Contratos do incremento histórico

Service Desk usará um contexto explícito de importação histórica nos modelos do domínio. Criação operacional continua exigindo status inicial. O contexto histórico preservará status e autor inativos sem reativar grants, mantendo validações de conta, unidade, existência, autoria e campos obrigatórios. Atualizações ainda validam imutabilidade de ownership. Eventos e snapshots são append-only; qualquer delta de conteúdo exige novo registro de origem. SLA conserva condições, timezone, versão de política/calendário, hash e datas; não recalcula prazo.

Anexos começam com domínios tipados de Project/Task e insumo limitado de bytes. Nenhuma classe polimórfica vem do usuário. Prévia verifica Base64/tamanho/SHA256; execução grava e relê o objeto físico antes de registrar correspondência. Reconciliação verifica novamente bytes e vínculo. Não marca antivírus como aprovado nem toca datas do registro pai ou dispara análise/jobs. Falhas não autorizam aceite.

## Gate de revisão — antes do checkpoint

- [x] RED de download importado sem autoridade/scan: oito falhas reais e controle nativo aprovado.
- [x] RED de falha no evento final do lote: bytes persistiram e referência privada estava ausente.
- [x] RED de recovery de pesquisas históricas: quatro falhas reais, incluindo registros aceitos; dois controles nativos aprovados.
- [x] Confirmar classe PG no RED concorrente com TracePoint explicitamente habilitado em todas as threads; somente depois ajustar lock.
- [x] GREEN do guard autenticado de blobs, sem redirect, com hash de scan e hash original do staging, original presente e autorização nativa atual.
- [x] GREEN do participante transacional de compensação: chave nova registrada antes de upload, promoção entre savepoints, limpeza após rollback externo e referência privada persistida quando a remoção falha; KEEP dos blobs nativos.
- [x] GREEN do filtro de origem histórica no recovery e no job direto de primeira resposta; aceite NICO não autoriza efeitos retroativos.
- [ ] RED/GREEN da reutilização operacional de signed_id importado via guard SD compartilhado (MessageBuilder/OutboundAttachments/widget).
- [ ] Regressão dos 43 casos Central, gates NICO da outra frente, lint focal e revisão independente antes do checkpoint coordenado pelo root.

## Próximo bloco interno após checkpoint

### Prioridade de mídia antes de ampliar domínios

1. RED/GREEN de reutilização de signed_id: MessageBuilder, widget e o último guard antes do serviço de canal devem consultar a origem importada, scan e permissão atual, além das regras SD existentes. Nenhum envio real nos testes.
2. Ledger `JrcMigrations::MediaObject`, migration aditiva `20261102203000`: reserva gerada na prévia validada, antes de qualquer upload, com tenant/lote/item, service/key inédita, SHA256 e tamanho. Fonte e identidade de armazenamento imutáveis no banco; chave nunca vem do operador. Prévia repetida mantém reserva planejada. Reserva limpa ganha nova chave em nova geração, preservando evidência anterior.
3. Execute usa a reserva planejada; Blob, attachment, mapping e estado attached do ledger confirmam na mesma transação. Falha abrupta mantém ledger prévio e permite localizar objeto físico mesmo sem Blob no banco. O participante de rollback continua acelerando compensação normal, sem ser confundido com a durabilidade do ledger.
4. Recovery autorizado: Account NO KEY UPDATE → Batch → Item/ledger, revalidação e claim RECOVERING com token persistido; depois I/O de remoção fora da transação, finalização por CAS do token. Execute recusa reserva em recovery. Qualquer Blob atual no mesmo service/key é KEEP; não apagar por ausência de mapping. Falha de delete persiste cleanup_required e uma nova tentativa é idempotente. O primeiro incremento preserva o lock atual do Execute durante upload/readback; separar esse upload em fases exigirá testes de fencing próprios.
5. Scanner explícito por item no produto: conta/admin e autoridade nativa do pai, origem e hash revalidados; INSTREAM local fora da transação; conta/ator/identidade/bytes novamente conferidos antes de persistir a prova e auditar MEDIA_SCANNED. Infected/unavailable continuam bloqueados. Não expor key, tokens ou insumo Base64 nas respostas/eventos.
6. RED preparado: protocolo5 + scan5 + crash1 (child Linux sintético, SIGKILL real após upload e antes commit, somente DB allowlist). Após implementação, exigir prova física pós-crash, UI funcional, preservação KEEP e regressões dos gates anteriores. Nenhuma fonte real nem serviço de antivírus externo será presumido.

1. Projetos: membros/roles existentes, boards e colunas, comentários/autoria e dependências. Adapters específicos validarão tenant e projeto; dependências devem usar a regra nativa contra ciclos, não apenas a validação simples do modelo.
2. Service Desk: versões de lifecycle existentes, transições, ciclos/pausas SLA, notas e aprovações históricas; depois anexos tipados de notas. Preservar autoria, ordem, estado e decisões sem rodar motor de transição, relógio, pesquisa ou notificação.
3. CRM/contratos/documentos: catálogo de pipelines/etapas, negócios e atividades; propostas/contratos e versões documentais com relações, valores e bytes físicos reconciliados.
4. Conversas/telefonia/Backoffice/relacionamento/ativos/conhecimento: mapear cada modelo real e dependência a adapter próprio, preservando importadores existentes. Não substituir essa implementação por um adapter polimórfico genérico que pule validações.

Esses blocos são trabalho de software ainda pendente. Extração oficial, dados/credenciais reais, homologação de jornadas, aceite operacional, cutover e legado continuam separados e não são simulados por testes.
