# CP2 - modelo de dados executavel (registrado antes das migrations)

Base: consolidado CP1 validado. CP2-D01/D02 APROVADAS, opcao A; SD-D01...SD-D05 preservadas.
Somente fundacao de dados/dominio. Nenhuma interface, endpoint, job ou integracao externa.

## Padroes comuns

PK id BIGINT nativa de create_table; account_id BIGINT NOT NULL em TODAS as 13 tabelas.
Timestamps nativos (somente created_at em eventos/snapshots); referencias de Contact e
Conversation usam INTEGER correspondente aos IDs legados, AccountUser/Team usam BIGINT.
Nao converter IDs nativos. FKs compostas preservam Account e, entre entidades do dominio,
Unidade. Primary key continua simples; nao introduzir PK composta nem default_scope.
Colunas opcionais: categoria, fila, equipe e responsavel ainda nao atribuido. Solicitante,
status, prioridade, criador e unidade sao obrigatorios. Nao ha dados demonstrativos/seeds.
Catalogos de status/prioridade/categoria sao configuracoes por unidade neste nucleo; nao
ha heranca implicita de outro escopo. Campos active e lock_version seguem padroes nativos.

## Justificativa dos unicos objetos adicionais nas tabelas nativas

Quatro indices UNIQUE (account_id, id), com nomes jrc_sd_ref_account_users,
jrc_sd_ref_contacts, jrc_sd_ref_teams, jrc_sd_ref_conversations. Uma FK simples garantiria
somente a existencia do ID, NAO sua Account. Esses indices permitem FKs compostas sem
alterar nenhuma coluna, valor, PK, validacao ou model nativo. Criacao CONCURRENTLY em migration
separada (sem transacao DDL). Remocao pelo nome exclusivo em rollback, apos as FKs do modulo.
Nao remover indices preexistentes. Se houver indice residual INVALID de tentativa abortada,
parar a aplicacao da migration e inspecionar no ambiente local; nao ocultar com if_not_exists.

## Indices e constraints comuns

OperatorCompany/Unit: UNIQUE(account_id,id) para alvo de FK.
Registros por unidade: UNIQUE(account_id,unit_id,id) onde referenciados, e indice composto de
consulta (account_id,unit_id,...). Code unico por unidade, ou por operadora para codigo de unidade.
FKs sem CASCADE para proteger historico; exclusao de registros nativos referenciados pode ser
recusada. Revogar membership usa active=false, nao delete. Nao criar purge ou alterar jobs nativos.
Bool NOT NULL; strings obrigatorias com CHECK btrim <> ''; JSONB com CHECK tipo object.
Membros inativos nunca concedem acesso; FK prova coerencia, atividade e acao sao revalidadas
nos services/policies. FKs nao substituem autorizacao nem RLS; SQL privilegiado continua confiavel.

## Fichas de tabelas

### jrc_service_desk_operator_companies

- TABELA: `jrc_service_desk_operator_companies`.
- FINALIDADE: Empresa operadora propria, separada do cliente.
- ACCOUNT BOUNDARY: Account.
- COLUNAS: id, account_id; code, name, active, lock_version (ver migration para limites/defaults exatos).
- FKs: Account.
- INDICES: chaves de referencia e consulta descritas acima; detalhes abaixo.
- RELACOES: units.
- JUSTIFICATIVA: SD-D01/CP2-D01: proprietario operacional, sem reutilizar empresas-clientes.

### jrc_service_desk_units

- TABELA: `jrc_service_desk_units`.
- FINALIDADE: Unidade operacional de uma operadora.
- ACCOUNT BOUNDARY: Account + operator_company_id obrigatorio.
- COLUNAS: id, account_id; operator_company_id, code, name, active, lock_version (ver migration para limites/defaults exatos).
- FKs: Account; (account_id, operator_company_id) -> operator_companies.
- INDICES: chaves de referencia e consulta descritas acima; detalhes abaixo.
- RELACOES: memberships, configuracoes, tickets.
- JUSTIFICATIVA: Unidade obrigatoria, sem fallback/default ou hierarquia variavel.

### jrc_service_desk_unit_memberships

- TABELA: `jrc_service_desk_unit_memberships`.
- FINALIDADE: Vinculo explicito de escopo, NAO RBAC.
- ACCOUNT BOUNDARY: Account + unit_id + AccountUser da mesma Account.
- COLUNAS: id, account_id; unit_id, account_user_id, active (default false), lock_version (ver migration para limites/defaults exatos).
- FKs: Account; unidade composta; AccountUser composto.
- INDICES: chaves de referencia e consulta descritas acima; detalhes abaixo.
- RELACOES: AccountUser nativo; unidade; autoria/atribuicao de tickets.
- JUSTIFICATIVA: CP2-D02: nenhum campo role/permissions; revogacao por active=false.

### jrc_service_desk_ticket_statuses

- TABELA: `jrc_service_desk_ticket_statuses`.
- FINALIDADE: Estados configuraveis, separados das fases tecnicas.
- ACCOUNT BOUNDARY: Account + unit_id.
- COLUNAS: id, account_id; unit_id, code, name, active, position, phase, initial, lock_version (ver migration para limites/defaults exatos).
- FKs: Account; unidade composta.
- INDICES: chaves de referencia e consulta descritas acima; detalhes abaixo.
- RELACOES: tickets.
- JUSTIFICATIVA: Estado inicial e escolhido explicitamente; sem seed/taxonomia ficticia.

### jrc_service_desk_priorities

- TABELA: `jrc_service_desk_priorities`.
- FINALIDADE: Prioridade configuravel.
- ACCOUNT BOUNDARY: Account + unit_id.
- COLUNAS: id, account_id; unit_id, code, name, active, position, lock_version (ver migration para limites/defaults exatos).
- FKs: Account; unidade composta.
- INDICES: chaves de referencia e consulta descritas acima; detalhes abaixo.
- RELACOES: tickets.
- JUSTIFICATIVA: Distinta de status e sem copiar enum de Conversas.

### jrc_service_desk_categories

- TABELA: `jrc_service_desk_categories`.
- FINALIDADE: Classificacao configuravel.
- ACCOUNT BOUNDARY: Account + unit_id.
- COLUNAS: id, account_id; unit_id, code, name, active, lock_version (ver migration para limites/defaults exatos).
- FKs: Account; unidade composta.
- INDICES: chaves de referencia e consulta descritas acima; detalhes abaixo.
- RELACOES: tickets.
- JUSTIFICATIVA: Sem impor segmento/hierarquia de categorias nao solicitada.

### jrc_service_desk_queues

- TABELA: `jrc_service_desk_queues`.
- FINALIDADE: Fila operacional Service Desk.
- ACCOUNT BOUNDARY: Account + unit_id.
- COLUNAS: id, account_id; unit_id, code, name, active, team_id opcional, lock_version (ver migration para limites/defaults exatos).
- FKs: Account; unidade composta; Team composto.
- INDICES: chaves de referencia e consulta descritas acima; detalhes abaixo.
- RELACOES: tickets; Team nativo.
- JUSTIFICATIVA: Fila nao e unidade, permissao nem fila de voz; sem distribuicao automatica.

### jrc_service_desk_tickets

- TABELA: `jrc_service_desk_tickets`.
- FINALIDADE: Processo operacional do Service Desk.
- ACCOUNT BOUNDARY: Account + exatamente uma unit_id NOT NULL.
- COLUNAS: id, account_id; unit_id, title, description, requester_id, status_id, priority_id, category_id, queue_id, team_id, assignee_membership_id, created_by_membership_id, origin_channel, opened_at, idempotency_key, request_fingerprint, lock_version (ver migration para limites/defaults exatos).
- FKs: Account; unidade; configuracoes, autoria e atribuicao compostas (account_id,unit_id,id); Contact/Team compostos.
- INDICES: chaves de referencia e consulta descritas acima; detalhes abaixo.
- RELACOES: notas, eventos, snapshots/marcos e vinculos de conversas.
- JUSTIFICATIVA: Unica fonte de dados; operadora derivada da unidade; nenhuma coluna project_id.

### jrc_service_desk_ticket_events

- TABELA: `jrc_service_desk_ticket_events`.
- FINALIDADE: Historico relevante append-only no dominio.
- ACCOUNT BOUNDARY: Account + unit_id + ticket_id.
- COLUNAS: id, account_id; unit_id, ticket_id, actor_membership_id, event_type, data JSONB, correlation_id, created_at (ver migration para limites/defaults exatos).
- FKs: Account; unidade; ticket e ator compostos.
- INDICES: chaves de referencia e consulta descritas acima; detalhes abaixo.
- RELACOES: ticket; ator AccountUser via membership.
- JUSTIFICATIVA: Historico nao aciona dispatcher/jobs; nao armazena payload financeiro ou corpo de notas.

### jrc_service_desk_ticket_notes

- TABELA: `jrc_service_desk_ticket_notes`.
- FINALIDADE: Notas INTERNAS do ticket, nao mensagens de canal.
- ACCOUNT BOUNDARY: Account + unit_id + ticket_id.
- COLUNAS: id, account_id; unit_id, ticket_id, author_membership_id, body, visibility=internal, idempotency_key, request_fingerprint, timestamps (ver migration para limites/defaults exatos).
- FKs: Account; unidade; ticket e autor compostos.
- INDICES: chaves de referencia e consulta descritas acima; detalhes abaixo.
- RELACOES: ticket; Active Storage nativo (associacao, sem upload/download neste CP2).
- JUSTIFICATIVA: Nenhuma publicacao implicita; comandos rejeitam blob_id, signed_id e files.

### jrc_service_desk_sla_snapshots

- TABELA: `jrc_service_desk_sla_snapshots`.
- FINALIDADE: Versao imutavel no dominio das condicoes aplicadas.
- ACCOUNT BOUNDARY: Account + unit_id + ticket_id.
- COLUNAS: id, account_id; unit_id, ticket_id, version, source_system/reference/version, contract_conditions JSONB, policy_key/version, policy_conditions JSONB, calendar_key/version/scope, calendar_conditions JSONB, timezone, captured_at, applied_at, payload_digest, created_at (ver migration para limites/defaults exatos).
- FKs: Account; unidade; ticket composto.
- INDICES: chaves de referencia e consulta descritas acima; detalhes abaixo.
- RELACOES: ticket e sla_milestones.
- JUSTIFICATIVA: SD-D02/SD-D04: evidencia local sem integrar ERP nem inventar calendario/prazos.

### jrc_service_desk_sla_milestones

- TABELA: `jrc_service_desk_sla_milestones`.
- FINALIDADE: Marcos de primeira resposta e resolucao.
- ACCOUNT BOUNDARY: Account + unit_id + ticket_id + snapshot_id coerentes.
- COLUNAS: id, account_id; unit_id, ticket_id, sla_snapshot_id, kind, due_at, calculated_at, calculator_version, achieved_at, lock_version, timestamps (ver migration para limites/defaults exatos).
- FKs: Account; unidade; ticket composto; snapshot composto incluindo ticket_id.
- INDICES: chaves de referencia e consulta descritas acima; detalhes abaixo.
- RELACOES: snapshot e ticket.
- JUSTIFICATIVA: Prazo nulo significa pendente de calculo; sem fallback 24x7 ou engine de SLA.

### jrc_service_desk_ticket_conversations

- TABELA: `jrc_service_desk_ticket_conversations`.
- FINALIDADE: Vinculo a conversa nativa sem copiar mensagens.
- ACCOUNT BOUNDARY: Account + unit_id + ticket_id.
- COLUNAS: id, account_id; unit_id, ticket_id, conversation_id interno, linked_by_membership_id, timestamps (ver migration para limites/defaults exatos).
- FKs: Account; unidade; ticket/ator compostos; Conversation composto.
- INDICES: chaves de referencia e consulta descritas acima; detalhes abaixo.
- RELACOES: Conversation nativa e ticket.
- JUSTIFICATIVA: Vincular/consultar exige tambem policy nativa da conversa; nenhum envio.

## Indices especificos

- Operadora: UNIQUE(account_id,code). Unidade: UNIQUE(account_id,operator_company_id,code).
- Membership: UNIQUE(account_id,unit_id,account_user_id), (account_id,account_user_id,active,unit_id).
- Configuracoes/fila: UNIQUE(account_id,unit_id,code); status inicial ativo unico por unidade
  com indice parcial, CHECK initial implica phase=open; position >= 0 quando aplicavel.
- Ticket: UNIQUE(account_id,unit_id,created_by_membership_id,idempotency_key); indices de
  unidade/data/id, status/data, fila/data, responsavel, equipe, prioridade e categoria.
- Notas: UNIQUE(account_id,unit_id,ticket_id,author_membership_id,idempotency_key), fingerprint SHA-256.
- Snapshot: UNIQUE(account_id,unit_id,ticket_id,payload_digest) evita reaplicar a mesma evidencia capturada.
- Eventos/notas: (account_id,unit_id,ticket_id,created_at,id), autoria e tipo de evento.
- Snapshot: UNIQUE(account_id,unit_id,ticket_id,version), version > 0; hash SHA-256 do payload
  canonico; UNIQUE(account_id,unit_id,ticket_id,id) como alvo de FK do marco.
- Marco: UNIQUE(account_id,unit_id,sla_snapshot_id,kind); kind primeira resposta/resolucao;
  (account_id,unit_id,due_at); prazo preenchido exige calculated_at + calculator_version.
- Conversa vinculada: UNIQUE(account_id,unit_id,ticket_id,conversation_id) e consulta reversa.

## Limites deliberados e seguranca

Sem tabela de calendario mestre nesta fundacao: preservam-se snapshots explicitos de calendario,
com fuso e versao; precedencia, importacao de feriados e calculador nao foram implementados.
Sem tabela de pausas antes da regra temporal/fluxo correspondente. Marcos vazios NAO sao SLA cumprido.
Snapshots/eventos/notas sao append-only nas operacoes ActiveRecord e nos services expostos:
sem update/delete de dominio. Nao alegar inviolabilidade contra SQL privilegiado/update_all;
nenhum trigger ou mudanca global de schema_format foi introduzido. Protecao SQL privilegiada e
retencao/purge precisam de revisao especifica antes de conceder operacoes destrutivas futuras.
Sem alteracao manual do schema.rb. No Docker/local, migrar e gerar schema pelo Rails.
Rollback do core recusa exclusao se QUALQUER tabela Service Desk tiver dados. Com tabelas
vazias, remove somente objetos do CP2 em ordem inversa. Preservar backup antes da migration.
Fronteira Projetos continua exclusivamente documental: sem FK/project_id, model, flag ou tabela.
