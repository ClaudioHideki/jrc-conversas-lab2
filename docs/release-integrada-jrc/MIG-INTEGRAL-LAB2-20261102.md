# Central de Migração — cobertura incremental de 02/11/2026

Este documento registra software local e fixtures. Nenhuma fonte real foi carregada, nenhum aceite funcional foi dado em nome do usuário, e não houve produção, cutover, dump, backup ou restore. A Central **não está completa**.

## Base funcional implementada

Módulo separado `JrcMigrations`, preservando DataImports Contacts/Intercom. Lotes versionados guardam fonte, mapeamento, hash e insumos originais; itens registram decisão, erro, destino, hash e estado anterior no delta. A prévia é obrigatória antes da execução. A execução valida os modelos reais e escreve apenas colunas persistidas sem callbacks, dispatcher ou jobs. Identidades ambíguas ficam para revisão, sem merge automático. Conta, usuário, relações, versão de origem e alterações locais são revalidados.

UI própria em Configurações de dados → Central de Migração: JSON/CSV limitado a 500 registros/2 MB, mapeamento por coluna, prévia, execução explícita, reprocessamento por nova prévia, download de erros e reconciliação. Aceite do NICO exige comparação de hashes/relações e nota funcional explícita. A reconciliação declara `official_source_verified: false`: compara staging e destino, sem certificar a integralidade da extração oficial.

## Matriz de domínios

| Domínio / requisito | Estado nesta Central | Próximo trabalho concreto |
| --- | --- | --- |
| Empresas / contatos — MIG-L0440, MIG-L0011–0015, MIG-L0017–0018 | Adapters ligados às tabelas existentes `companies` e `contacts`, datas originais, chave por fonte/tenant, delta, bloqueio de ambiguidade e relações mesma conta | Expandir taxonomias, endereços, pontos de contato, grupos/unidades e correspondência completa de responsáveis; revisão/merge assistido ainda não tem ação na Central |
| Organização, usuários, equipes, RBAC — MIG-L0439, MIG-L0416–0417 | Apenas referências a registros existentes são validadas; não há criação ou concessão automática de privilégios | Adapters de estrutura organizacional e correspondências explícitas por papel/unidade, preservando regras dos módulos reais |
| Projetos / tarefas — MIG-L0446 | Adapters `projects` e `project_tasks` ligados aos modelos reais, com dono, contato/empresa, status, datas, prioridade, labels e subtarefa. `lock_version` avança no delta; datas impossíveis e relações contraditórias são rejeitadas | Membros precisam existir e são validados; adapters de membros, boards/colunas, comentários e dependências ainda pendentes |
| Service Desk — MIG-L0444 | Quatro adapters: Ticket, TicketEvent, SlaSnapshot e SlaMilestone. Contexto histórico próprio mantém status final, atores/estados inativos existentes, datas e SLA original; relações de tenant/unidade continuam validadas. Sete casos aprovados | Ciclos/pausas/transições, notas, aprovações e pesquisas ainda pendentes. Revisão identificou recovery posterior de pesquisa a partir do evento importado; RED preparado antes da correção |
| Anexos — MIG-L0451, MIG-L0519 | Dois adapters tipados Project/Task gravam bytes reais no ActiveStorage, verificam SHA256/tamanho/leitura, preservam data e chave de origem. Sete casos aprovados. Arquivo não recebe scan clean presumido | Revisão identificou falta de proteção no download assinado e compensação incompleta após rollback do lote; RED preparado. Arquivos de notas/documentos e limites de grande volume ainda pendentes |
| Contratos/documentos — MIG-L0441 | Modelos comerciais/documentais existentes; não ligados | Preservar sales order/owner, vigência, valores, versões, assinatura e arquivos com validação relacional |
| CRM/propostas — MIG-L0442 | Não ligado | Adapters por organização/contato/etapa/pipeline/atividade e prova do Cliente 360 |
| Atendimento/conversas — MIG-L0443 | Importadores atuais preservados; sem adapter novo da Central | Identidade, inbox, agente, Team, direção, timestamps, IDs e mídia sem envio de mensagens ou automações |
| Telefonia — MIG-L0445 | Não ligado | Fonte real autorizada, metadados, gravações e vínculos; nenhuma credencial foi presumida |
| Backoffice/aprovações/relacionamento/pesquisas/ativos/conhecimento — MIG-L0447–0450 | Modelos e módulos existentes não equivalem a adapters da Central | Adapters específicos com dependências, decisões históricas, autoria, arquivos e testes próprios |
| Timeline/Cliente 360 — MIG-L0452, MIG-L0460 | Empresas/contatos criados nos modelos do produto; teste de relação local, sem homologação completa do Cliente 360 | Carregar eventos históricos dos demais domínios e validar jornadas ponta a ponta |
| NICO — MIG-L0395, MIG-L0463, MIG-L0534 | Helper de tenant/aceite implementado; nega qualquer mapping pendente, inclusive attachments sem account_id por vínculo tipado. Frente NICO comprovou 51 casos no gate recente | Revisões de concorrência de revogação, recibo de efeito nativo e agregados continuam com a frente NICO; não declarar cobertura transversal completa |

## Pipeline e operação ainda pendentes

| Requisitos | Estado / limite |
| --- | --- |
| MIG-L0428, MIG-L0430–0432, MIG-L0434–0435, MIG-L0437 | Base funcional local e dez adapters do catálogo comprovados por 43 casos; quatro blockers de revisão em correção antes do checkpoint. Não extrapolar para domínios sem adapter |
| MIG-L0433 | Timeline de operadores/ações implementada, com migration202000 e guard SQL de UPDATE/DELETE/TRUNCATE; RED observado e GREEN no pipeline17/17. UI/API paginam 50 eventos por cursor |
| MIG-L0429, MIG-L0406–0411 | Conectores/extratores e inventário oficial não implementados; UI recebe arquivos fornecidos pelo operador. Fonte, acesso, volumes e ponto de corte reais não foram inventados |
| MIG-L0424–0426 | Ambiguidade bloqueada e erro exportável; decisão humana de matching e merge com auditoria ainda pendente |
| MIG-L0436, MIG-L0396, MIG-L0537 | Estado anterior de delta preservado; rollback funcional do lote ainda não implementado. Backup/dump/restore excluídos desta execução |
| MIG-L0454–0464 | Fixtures locais não substituem amostra real, homologação quase completa, HOYA, relatórios, Communication Engine e aceite por responsáveis |
| MIG-L0466–0486 | Atividades operacionais de produção/hypercare/cutover/legado não executadas e não são marcadas concluídas por testes de software |

## Evidências sem somar execuções sobrepostas

Estado mais recente: **43 casos Central aprovados** = pipeline19 + projetos6 + ServiceDesk7 + arquivos7 + API4. A rodada `nico-boundary-and-domains-red.json` comprovou 36 desses casos e seis dos sete SD; a única falha SD era fixture com segundo status inicial na mesma unidade. A fixture foi corrigida, e os sete SD passaram em `nico-boundary-and-domains-green.json` (58/58 totais = NICO51 + SD7). Não houve alteração de aplicação Central entre essas duas rodadas. Logs/JSON ficam em `output/specs-20261102` do workspace pai.

Verificação estática do módulo/controlador/specs próprios: **28 arquivos RuboCop sem infrações**, `central-adapters-rubocop-final.log`. Os modelos SD alterados têm infrações preexistentes fora do trecho da mudança; esse resultado não é lint global. Vue focal mais recente **8/8**, `central-ui-history-green.log`; ESLint passou após rótulos/ajuda dos novos domínios. Não houve verificação visual autenticada.

Revisão independente abriu quatro blockers antes do checkpoint: (1) download de attachment importado via URL nativa sem revalidar autorização/scan; (2) arquivo físico sem compensação após falha no evento final do lote; (3) ordem Account/Project capaz de deadlock com auditoria humana; (4) recovery posterior capaz de transformar evento histórico SD em pesquisa. Os **18 testes RED** observaram 15 falhas de produto e três controles nativos aprovados. O diagnóstico concorrente foi refinado para observar todas as threads e confirmou `ActiveRecord::Deadlocked`/`PG::TRDeadlockDetected`, `central-lock-trace-threads-red.*`.

Após correções, **23/23 Central passaram** em `nico-central-consolidated-green.*`: downloads13 (inclui redirect/proxy/disk, reanexo/origem removida e scan posterior comparado ao SHA original), rollback3 (inclui falha do chamador após Execute retornar), concorrência1 e pesquisas6. A compensação registra apenas chaves novas antes do upload, acompanha os savepoints e persiste referência privada quando a remoção falha. Blobs nativos KEEP são preservados. Account usa `FOR NO KEY UPDATE`, que mantém exclusão entre importação/aceite/NICO e permite FK `KEY SHARE` da auditoria humana. Recovery e job de primeira resposta filtram o próprio evento importado, independentemente de aceite; eventos operacionais novos continuam válidos.

Limites desse gate: compensação em memória cobre rollback Ruby/SQL, **não** morte abrupta do processo durante upload; não foi testado crash recovery de armazenamento. Downloads importados exigem prova real do scanner local existente, e a Central ainda não oferece acionamento UI específico para scan Project/Task. Revisão transversal abriu próximo RED de reutilização de `signed_id` via MessageBuilder/OutboundAttachments/widget, que consultam o guard SD compartilhado; os 23 casos não certificam esse caminho ainda. Não somar esses 23 aos 43 anteriores como se uma rodada única ampla tivesse sido executada.

Os parágrafos abaixo preservam a evolução dos gates anteriores. Contagens e pendências antigas não substituem o estado mais recente acima.

- RED inicial: 14 casos Central por classes/rotas ausentes.
- Primeiro gate com migrações: 51 exemplos totais, 41 aprovados/10 falhas; 34 casos Conexões aprovados. Oito falhas Central tinham a mesma causa (`Contact.label_list` virtual em `insert_all!`); duas eram contrato HTTP/ParamsWrapper. Causas corrigidas.
- GREEN Central: **17/17**, arquivo `output/specs-20261102/central-pipeline-green.log` no workspace pai; 9,38 s + 42,98 s de boot. Empresas/contatos, zero dispatcher/IP lookup, delta e estado anterior, duplicidade, edição concorrente, relações, API/RBAC, reconciliação e gate múltiplos mappings.
- Vue focal: **7/7** = Central 3 + parser CSV 2 + histórico Conexões 2. Não somar com testes anteriores sobrepostos.
- Migrações 130000 (Central) e 201000 (capability Flow da outra frente) aplicadas somente em `jrc_durable_global_audit_test`; schema reconciliado seletivamente, inclusive SQL adicional dos checks/triggers.
- Sem verificação visual em navegador, carga real, envio real, domínio completo ou aceite operacional.

Incremento em validação: rejeição de referência numérica malformada e data impossível, registro sanitizado de erro observado de conexão, proteção de edição concorrente por lock_version, auditoria de lote e projetos/tarefas. CSV estrito comprovado por RED 2/3 e GREEN 3/3 em teste nativo Node (`migration-csv-green.log`). Service Desk possui seis novos testes preparados, sem implementação nem execução ainda.

Gate Rails 272 exemplos (`output/specs-20261102/lab2-integral-rails-red.log/.json` no workspace pai): Conexões35/35, Central pipeline17/17 + API3/3 + projects4/5. Falha nova esperada: formulário antigo consegue sobrescrever delta sem avanço de lock_version; correção escrita, GREEN pendente. Histórico append-only, relações/datas estritas e projetos/tarefas iniciais comprovados. NICO core/domain/effects18/18; novos snapshot5/6 e indirect6/6 falharam (agente NICO responsável). Regressões de campanha recovery33/55, demais127/127; root investiga22falhas. Não somar com suítes anteriores sobrepostas.

Próximo gate: correção de optimistic locking (RED real confirmado), novo RED para data `starts_on` impossível, Service Desk5 e anexos físicos Project5 preparados. ESLint dos arquivos Vue/JS alterados passou após formatação; teste Vue de histórico de lote passou junto aos demais focais (8/8: Central4, parser2, históricoConexões2). RuboCop identificou complexidade em Base (helpers extraídos) e duas linhas formatadas; rerun estático pendente.

UI focal mais recente: **8/8**, `output/specs-20261102/central-ui-history-green.log`, incluindo paginação das operações de lote. Apenas fixtures em montagem Vue; verificação visual autenticada continua pendente. Próximo RED Rails preparado: Project6 (5 esperados GREEN + data inválida1 RED), ServiceDesk6 RED e anexos Project5 RED.
