# CP6 - matriz ordenada de migrations

**CANDIDATO PARA HOMOLOGAÇÃO — VALIDAÇÃO NATIVA PENDENTE**

**PENDENTE — validação nativa em Docker/servidor**

Nenhuma migration nova no CP6. As 204 anteriores sao identicas; abaixo, as tres do Service Desk, na ordem. 20 tabelas SD, 69 indices declarados (incluindo 4 nativos auxiliares), 79 FKs e 30 CHECKs; 2 colunas de ticket acrescentadas pelo ciclo. Numeros do gravador de declaracoes, NAO de banco migrado.

| MIGRATION | TABELAS/INDICES/FKS/CHECKS | ROLLBACK | RISCO | STATUS |
|---|---|---|---|---|
| db/migrate/20260925190000_add_jrc_service_desk_reference_keys.rb | {"add_index": 4} | Remover somente depois das FKs dependentes, por decisao explicita; nao automatizado. | Indices CONCURRENTLY fora de transacao; verificar pg_index.indisvalid apos interrupcao. | PENDENTE DE EXECUÇÃO NATIVA |
| db/migrate/20260925190100_create_jrc_service_desk_core.rb | {"create_table": 13, "add_index": 46, "add_check_constraint": 23, "add_foreign_key": 45} | Core recusa rollback se qualquer tabela tiver dados. Caminho vazio somente em banco descartavel distinto. | FKs compostas e integridade entre conta/unidade; podem impedir exclusao/merge nativo. | PENDENTE DE EXECUÇÃO NATIVA |
| db/migrate/20260928120000_add_jrc_service_desk_lifecycle.rb | {"create_table": 7, "add_index": 19, "add_check_constraint": 7, "add_foreign_key": 34, "add_column": 2} | Recusa quando ha dados novos ou ticket vinculado. Remocao de FK circular antes de tabelas, somente caminho vazio. | Referencia circular policy/current_version; ciclos e snapshots; verificar dump/schema e TZInfo. | PENDENTE DE EXECUÇÃO NATIVA |

## db/migrate/20260925190000_add_jrc_service_desk_reference_keys.rb

SHA-256: `0e8bfe6a439c6e3eeb994db4007f871eb382bc679922d4f4b8c2ac67517afa1d`

### FKs / indices / checks

| ACAO | ALVO/COLUNAS | DEFINICAO |
|---|---|---|
| add_index | ["account_users", ["account_id", "id"]] | {"unique": true, "name": "jrc_sd_ref_account_users", "algorithm": "concurrently"} |
| add_index | ["contacts", ["account_id", "id"]] | {"unique": true, "name": "jrc_sd_ref_contacts", "algorithm": "concurrently"} |
| add_index | ["teams", ["account_id", "id"]] | {"unique": true, "name": "jrc_sd_ref_teams", "algorithm": "concurrently"} |
| add_index | ["conversations", ["account_id", "id"]] | {"unique": true, "name": "jrc_sd_ref_conversations", "algorithm": "concurrently"} |


## db/migrate/20260925190100_create_jrc_service_desk_core.rb

SHA-256: `403be1e906573f90057ecb9bae0bc0c831748800d6a9f8ff9bab832411d97562`

### jrc_service_desk_operator_companies

| TIPO/DSL | COLUNA | OPCOES |
|---|---|---|
| bigint | ["account_id"] | {"null": false} |
| string | ["code"] | {"null": false, "limit": 80} |
| string | ["name"] | {"null": false, "limit": 255} |
| boolean | ["active"] | {"null": false, "default": true} |
| integer | ["lock_version"] | {"null": false, "default": 0} |
| timestamps | [] | {} |

### jrc_service_desk_units

| TIPO/DSL | COLUNA | OPCOES |
|---|---|---|
| bigint | ["account_id"] | {"null": false} |
| bigint | ["operator_company_id"] | {"null": false} |
| string | ["code"] | {"null": false, "limit": 80} |
| string | ["name"] | {"null": false, "limit": 255} |
| boolean | ["active"] | {"null": false, "default": true} |
| integer | ["lock_version"] | {"null": false, "default": 0} |
| timestamps | [] | {} |

### jrc_service_desk_unit_memberships

| TIPO/DSL | COLUNA | OPCOES |
|---|---|---|
| bigint | ["account_id"] | {"null": false} |
| bigint | ["unit_id"] | {"null": false} |
| bigint | ["account_user_id"] | {"null": false} |
| boolean | ["active"] | {"null": false, "default": false} |
| integer | ["lock_version"] | {"null": false, "default": 0} |
| timestamps | [] | {} |

### jrc_service_desk_ticket_statuses

| TIPO/DSL | COLUNA | OPCOES |
|---|---|---|
| bigint | ["account_id"] | {"null": false} |
| bigint | ["unit_id"] | {"null": false} |
| string | ["code"] | {"null": false, "limit": 80} |
| string | ["name"] | {"null": false, "limit": 255} |
| boolean | ["active"] | {"null": false, "default": true} |
| integer | ["lock_version"] | {"null": false, "default": 0} |
| timestamps | [] | {} |
| string | ["phase"] | {"null": false, "limit": 24} |
| integer | ["position"] | {"null": false, "default": 0} |
| boolean | ["initial"] | {"null": false, "default": false} |

### jrc_service_desk_priorities

| TIPO/DSL | COLUNA | OPCOES |
|---|---|---|
| bigint | ["account_id"] | {"null": false} |
| bigint | ["unit_id"] | {"null": false} |
| string | ["code"] | {"null": false, "limit": 80} |
| string | ["name"] | {"null": false, "limit": 255} |
| boolean | ["active"] | {"null": false, "default": true} |
| integer | ["lock_version"] | {"null": false, "default": 0} |
| timestamps | [] | {} |
| integer | ["position"] | {"null": false} |

### jrc_service_desk_categories

| TIPO/DSL | COLUNA | OPCOES |
|---|---|---|
| bigint | ["account_id"] | {"null": false} |
| bigint | ["unit_id"] | {"null": false} |
| string | ["code"] | {"null": false, "limit": 80} |
| string | ["name"] | {"null": false, "limit": 255} |
| boolean | ["active"] | {"null": false, "default": true} |
| integer | ["lock_version"] | {"null": false, "default": 0} |
| timestamps | [] | {} |

### jrc_service_desk_queues

| TIPO/DSL | COLUNA | OPCOES |
|---|---|---|
| bigint | ["account_id"] | {"null": false} |
| bigint | ["unit_id"] | {"null": false} |
| string | ["code"] | {"null": false, "limit": 80} |
| string | ["name"] | {"null": false, "limit": 255} |
| boolean | ["active"] | {"null": false, "default": true} |
| integer | ["lock_version"] | {"null": false, "default": 0} |
| timestamps | [] | {} |
| bigint | ["team_id"] | {} |

### jrc_service_desk_tickets

| TIPO/DSL | COLUNA | OPCOES |
|---|---|---|
| bigint | ["account_id"] | {"null": false} |
| bigint | ["unit_id"] | {"null": false} |
| string | ["title"] | {"null": false, "limit": 255} |
| text | ["description"] | {} |
| integer | ["requester_id"] | {"null": false} |
| bigint | ["status_id"] | {"null": false} |
| bigint | ["priority_id"] | {"null": false} |
| bigint | ["category_id"] | {} |
| bigint | ["queue_id"] | {} |
| bigint | ["team_id"] | {} |
| bigint | ["assignee_membership_id"] | {} |
| bigint | ["created_by_membership_id"] | {"null": false} |
| string | ["origin_channel"] | {"null": false, "limit": 80} |
| datetime | ["opened_at"] | {"null": false} |
| string | ["idempotency_key"] | {"null": false, "limit": 120} |
| string | ["request_fingerprint"] | {"null": false, "limit": 64} |
| integer | ["lock_version"] | {"null": false, "default": 0} |
| timestamps | [] | {} |

### jrc_service_desk_ticket_events

| TIPO/DSL | COLUNA | OPCOES |
|---|---|---|
| bigint | ["account_id"] | {"null": false} |
| bigint | ["unit_id"] | {"null": false} |
| bigint | ["ticket_id"] | {"null": false} |
| bigint | ["actor_membership_id"] | {"null": false} |
| string | ["event_type"] | {"null": false, "limit": 80} |
| jsonb | ["data"] | {"null": false, "default": {}} |
| string | ["correlation_id"] | {"limit": 120} |
| datetime | ["created_at"] | {"null": false} |

### jrc_service_desk_ticket_notes

| TIPO/DSL | COLUNA | OPCOES |
|---|---|---|
| bigint | ["account_id"] | {"null": false} |
| bigint | ["unit_id"] | {"null": false} |
| bigint | ["ticket_id"] | {"null": false} |
| bigint | ["author_membership_id"] | {"null": false} |
| text | ["body"] | {"null": false} |
| string | ["visibility"] | {"null": false, "default": "internal", "limit": 16} |
| string | ["idempotency_key"] | {"null": false, "limit": 120} |
| string | ["request_fingerprint"] | {"null": false, "limit": 64} |
| timestamps | [] | {} |

### jrc_service_desk_sla_snapshots

| TIPO/DSL | COLUNA | OPCOES |
|---|---|---|
| bigint | ["account_id"] | {"null": false} |
| bigint | ["unit_id"] | {"null": false} |
| bigint | ["ticket_id"] | {"null": false} |
| integer | ["version"] | {"null": false} |
| string | ["source_system"] | {"null": false, "limit": 255} |
| string | ["source_reference"] | {"null": false, "limit": 255} |
| string | ["source_version"] | {"null": false, "limit": 255} |
| string | ["policy_key"] | {"null": false, "limit": 255} |
| string | ["policy_version"] | {"null": false, "limit": 255} |
| string | ["calendar_key"] | {"null": false, "limit": 255} |
| string | ["calendar_version"] | {"null": false, "limit": 255} |
| string | ["calendar_scope"] | {"null": false, "limit": 24} |
| string | ["timezone"] | {"null": false, "limit": 100} |
| jsonb | ["contract_conditions"] | {"null": false} |
| jsonb | ["policy_conditions"] | {"null": false} |
| jsonb | ["calendar_conditions"] | {"null": false} |
| datetime | ["captured_at"] | {"null": false} |
| datetime | ["applied_at"] | {"null": false} |
| string | ["payload_digest"] | {"null": false, "limit": 64} |
| datetime | ["created_at"] | {"null": false} |

### jrc_service_desk_sla_milestones

| TIPO/DSL | COLUNA | OPCOES |
|---|---|---|
| bigint | ["account_id"] | {"null": false} |
| bigint | ["unit_id"] | {"null": false} |
| bigint | ["ticket_id"] | {"null": false} |
| bigint | ["sla_snapshot_id"] | {"null": false} |
| string | ["kind"] | {"null": false, "limit": 24} |
| datetime | ["due_at"] | {} |
| datetime | ["calculated_at"] | {} |
| string | ["calculator_version"] | {"limit": 100} |
| datetime | ["achieved_at"] | {} |
| integer | ["lock_version"] | {"null": false, "default": 0} |
| timestamps | [] | {} |

### jrc_service_desk_ticket_conversations

| TIPO/DSL | COLUNA | OPCOES |
|---|---|---|
| bigint | ["account_id"] | {"null": false} |
| bigint | ["unit_id"] | {"null": false} |
| bigint | ["ticket_id"] | {"null": false} |
| integer | ["conversation_id"] | {"null": false} |
| bigint | ["linked_by_membership_id"] | {"null": false} |
| timestamps | [] | {} |

### FKs / indices / checks

| ACAO | ALVO/COLUNAS | DEFINICAO |
|---|---|---|
| add_index | ["jrc_service_desk_operator_companies", ["account_id", "id"]] | {"unique": true, "name": "jrc_sd_operator_ref"} |
| add_index | ["jrc_service_desk_operator_companies", ["account_id", "code"]] | {"unique": true, "name": "jrc_sd_operator_code"} |
| add_check_constraint | ["jrc_service_desk_operator_companies", "btrim(code) <> '' AND btrim(name) <> ''"] | {"name": "jrc_sd_operator_companies_names"} |
| add_index | ["jrc_service_desk_units", ["account_id", "id"]] | {"unique": true, "name": "jrc_sd_unit_ref"} |
| add_index | ["jrc_service_desk_units", ["account_id", "operator_company_id", "code"]] | {"unique": true, "name": "jrc_sd_unit_code"} |
| add_check_constraint | ["jrc_service_desk_units", "btrim(code) <> '' AND btrim(name) <> ''"] | {"name": "jrc_sd_units_names"} |
| add_index | ["jrc_service_desk_unit_memberships", ["account_id", "unit_id", "id"]] | {"unique": true, "name": "jrc_sd_unit_memberships_scope_ref"} |
| add_index | ["jrc_service_desk_unit_memberships", ["account_id", "unit_id", "account_user_id"]] | {"unique": true, "name": "jrc_sd_membership_unique"} |
| add_index | ["jrc_service_desk_unit_memberships", ["account_id", "account_user_id", "active", "unit_id"]] | {"name": "jrc_sd_membership_access"} |
| add_check_constraint | ["jrc_service_desk_ticket_statuses", "phase IN ('open','waiting','resolved','closed','cancelled')"] | {"name": "jrc_sd_status_phase"} |
| add_check_constraint | ["jrc_service_desk_ticket_statuses", "NOT initial OR phase = 'open'"] | {"name": "jrc_sd_status_initial_phase"} |
| add_check_constraint | ["jrc_service_desk_ticket_statuses", "position >= 0"] | {"name": "jrc_sd_status_position"} |
| add_index | ["jrc_service_desk_ticket_statuses", ["account_id", "unit_id"]] | {"unique": true, "where": "initial AND active", "name": "jrc_sd_status_initial"} |
| add_check_constraint | ["jrc_service_desk_priorities", "position >= 0"] | {"name": "jrc_sd_priority_position"} |
| add_index | ["jrc_service_desk_queues", ["account_id", "team_id"]] | {"name": "jrc_sd_queue_team"} |
| add_index | ["jrc_service_desk_ticket_statuses", ["account_id", "unit_id", "id"]] | {"unique": true, "name": "jrc_sd_ticket_statuses_scope_ref"} |
| add_check_constraint | ["jrc_service_desk_ticket_statuses", "btrim(code) <> '' AND btrim(name) <> ''"] | {"name": "jrc_sd_ticket_statuses_names"} |
| add_index | ["jrc_service_desk_ticket_statuses", ["account_id", "unit_id", "code"]] | {"unique": true, "name": "jrc_sd_ticket_statuses_code"} |
| add_index | ["jrc_service_desk_ticket_statuses", ["account_id", "unit_id", "active"]] | {"name": "jrc_sd_ticket_statuses_active"} |
| add_index | ["jrc_service_desk_priorities", ["account_id", "unit_id", "id"]] | {"unique": true, "name": "jrc_sd_priorities_scope_ref"} |
| add_check_constraint | ["jrc_service_desk_priorities", "btrim(code) <> '' AND btrim(name) <> ''"] | {"name": "jrc_sd_priorities_names"} |
| add_index | ["jrc_service_desk_priorities", ["account_id", "unit_id", "code"]] | {"unique": true, "name": "jrc_sd_priorities_code"} |
| add_index | ["jrc_service_desk_priorities", ["account_id", "unit_id", "active"]] | {"name": "jrc_sd_priorities_active"} |
| add_index | ["jrc_service_desk_categories", ["account_id", "unit_id", "id"]] | {"unique": true, "name": "jrc_sd_categories_scope_ref"} |
| add_check_constraint | ["jrc_service_desk_categories", "btrim(code) <> '' AND btrim(name) <> ''"] | {"name": "jrc_sd_categories_names"} |
| add_index | ["jrc_service_desk_categories", ["account_id", "unit_id", "code"]] | {"unique": true, "name": "jrc_sd_categories_code"} |
| add_index | ["jrc_service_desk_categories", ["account_id", "unit_id", "active"]] | {"name": "jrc_sd_categories_active"} |
| add_index | ["jrc_service_desk_queues", ["account_id", "unit_id", "id"]] | {"unique": true, "name": "jrc_sd_queues_scope_ref"} |
| add_check_constraint | ["jrc_service_desk_queues", "btrim(code) <> '' AND btrim(name) <> ''"] | {"name": "jrc_sd_queues_names"} |
| add_index | ["jrc_service_desk_queues", ["account_id", "unit_id", "code"]] | {"unique": true, "name": "jrc_sd_queues_code"} |
| add_index | ["jrc_service_desk_queues", ["account_id", "unit_id", "active"]] | {"name": "jrc_sd_queues_active"} |
| add_index | ["jrc_service_desk_tickets", ["account_id", "unit_id", "id"]] | {"unique": true, "name": "jrc_sd_tickets_scope_ref"} |
| add_check_constraint | ["jrc_service_desk_tickets", "btrim(title) <> '' AND btrim(origin_channel) <> '' AND btrim(idempotency_key) <> ''"] | {"name": "jrc_sd_ticket_required_text"} |
| add_check_constraint | ["jrc_service_desk_tickets", "request_fingerprint ~ '^[a-f0-9]{64}$'"] | {"name": "jrc_sd_ticket_fingerprint"} |
| add_index | ["jrc_service_desk_tickets", ["account_id", "unit_id", "created_by_membership_id", "idempotency_key"]] | {"unique": true, "name": "jrc_sd_ticket_idempotency"} |
| add_index | ["jrc_service_desk_tickets", ["account_id", "unit_id", "created_at", "id"]] | {"name": "jrc_sd_ticket_recent"} |
| add_index | ["jrc_service_desk_tickets", ["account_id", "unit_id", "status_id", "created_at"]] | {"name": "jrc_sd_ticket_status_id"} |
| add_index | ["jrc_service_desk_tickets", ["account_id", "unit_id", "priority_id", "created_at"]] | {"name": "jrc_sd_ticket_priority_id"} |
| add_index | ["jrc_service_desk_tickets", ["account_id", "unit_id", "category_id", "created_at"]] | {"name": "jrc_sd_ticket_category_id"} |
| add_index | ["jrc_service_desk_tickets", ["account_id", "unit_id", "queue_id", "created_at"]] | {"name": "jrc_sd_ticket_queue_id"} |
| add_index | ["jrc_service_desk_tickets", ["account_id", "unit_id", "assignee_membership_id", "created_at"]] | {"name": "jrc_sd_ticket_assignee_membership_id"} |
| add_index | ["jrc_service_desk_tickets", ["account_id", "unit_id", "team_id", "created_at"]] | {"name": "jrc_sd_ticket_team_id"} |
| add_index | ["jrc_service_desk_tickets", ["account_id", "requester_id"]] | {"name": "jrc_sd_ticket_requester"} |
| add_check_constraint | ["jrc_service_desk_ticket_events", "jsonb_typeof(data) = 'object' AND btrim(event_type) <> ''"] | {"name": "jrc_sd_event_payload"} |
| add_index | ["jrc_service_desk_ticket_events", ["account_id", "unit_id", "ticket_id", "created_at", "id"]] | {"name": "jrc_sd_events_timeline"} |
| add_index | ["jrc_service_desk_ticket_events", ["account_id", "unit_id", "actor_membership_id"]] | {"name": "jrc_sd_event_actor"} |
| add_index | ["jrc_service_desk_ticket_events", ["account_id", "event_type", "created_at"]] | {"name": "jrc_sd_event_type"} |
| add_check_constraint | ["jrc_service_desk_ticket_notes", "visibility = 'internal' AND btrim(body) <> ''"] | {"name": "jrc_sd_note_internal"} |
| add_check_constraint | ["jrc_service_desk_ticket_notes", "btrim(idempotency_key) <> '' AND request_fingerprint ~ '^[a-f0-9]{64}$'"] | {"name": "jrc_sd_note_fingerprint"} |
| add_index | ["jrc_service_desk_ticket_notes", ["account_id", "unit_id", "ticket_id", "author_membership_id", "idempotency_key"]] | {"unique": true, "name": "jrc_sd_note_idempotency"} |
| add_index | ["jrc_service_desk_ticket_notes", ["account_id", "unit_id", "ticket_id", "created_at", "id"]] | {"name": "jrc_sd_notes_timeline"} |
| add_index | ["jrc_service_desk_ticket_notes", ["account_id", "unit_id", "author_membership_id"]] | {"name": "jrc_sd_note_author"} |
| add_index | ["jrc_service_desk_sla_snapshots", ["account_id", "unit_id", "ticket_id", "version"]] | {"unique": true, "name": "jrc_sd_snapshot_version"} |
| add_index | ["jrc_service_desk_sla_snapshots", ["account_id", "unit_id", "ticket_id", "payload_digest"]] | {"unique": true, "name": "jrc_sd_snapshot_deduplicate"} |
| add_index | ["jrc_service_desk_sla_snapshots", ["account_id", "unit_id", "ticket_id", "id"]] | {"unique": true, "name": "jrc_sd_snapshot_ref"} |
| add_check_constraint | ["jrc_service_desk_sla_snapshots", "version > 0"] | {"name": "jrc_sd_snapshot_version_positive"} |
| add_check_constraint | ["jrc_service_desk_sla_snapshots", "calendar_scope IN ('account','operator_company','unit')"] | {"name": "jrc_sd_snapshot_scope"} |
| add_check_constraint | ["jrc_service_desk_sla_snapshots", "payload_digest ~ '^[a-f0-9]{64}$'"] | {"name": "jrc_sd_snapshot_digest"} |
| add_check_constraint | ["jrc_service_desk_sla_snapshots", "jsonb_typeof(contract_conditions) = 'object'"] | {"name": "jrc_sd_snapshot_contract_conditions"} |
| add_check_constraint | ["jrc_service_desk_sla_snapshots", "jsonb_typeof(policy_conditions) = 'object'"] | {"name": "jrc_sd_snapshot_policy_conditions"} |
| add_check_constraint | ["jrc_service_desk_sla_snapshots", "jsonb_typeof(calendar_conditions) = 'object'"] | {"name": "jrc_sd_snapshot_calendar_conditions"} |
| add_index | ["jrc_service_desk_sla_milestones", ["account_id", "unit_id", "sla_snapshot_id", "kind"]] | {"unique": true, "name": "jrc_sd_milestone_unique"} |
| add_index | ["jrc_service_desk_sla_milestones", ["account_id", "unit_id", "ticket_id"]] | {"name": "jrc_sd_milestone_ticket"} |
| add_index | ["jrc_service_desk_sla_milestones", ["account_id", "unit_id", "due_at"]] | {"name": "jrc_sd_milestone_due"} |
| add_check_constraint | ["jrc_service_desk_sla_milestones", "kind IN ('first_response','resolution')"] | {"name": "jrc_sd_milestone_kind"} |
| add_check_constraint | ["jrc_service_desk_sla_milestones", "(due_at IS NULL AND calculated_at IS NULL AND calculator_version IS NULL) OR (due_at IS NOT NULL AND calculated_at IS NOT NULL AND calculator_version IS NOT NULL AND btrim(calculator_version) <> '')"] | {"name": "jrc_sd_milestone_calculation"} |
| add_index | ["jrc_service_desk_ticket_conversations", ["account_id", "unit_id", "ticket_id", "conversation_id"]] | {"unique": true, "name": "jrc_sd_conversation_link_unique"} |
| add_index | ["jrc_service_desk_ticket_conversations", ["account_id", "conversation_id"]] | {"name": "jrc_sd_conversation_reverse"} |
| add_index | ["jrc_service_desk_ticket_conversations", ["account_id", "unit_id", "linked_by_membership_id"]] | {"name": "jrc_sd_conversation_actor"} |
| add_foreign_key | ["jrc_service_desk_operator_companies", "accounts"] | {"column": "account_id", "name": "jrc_sd_operator_companies_account_fk"} |
| add_foreign_key | ["jrc_service_desk_units", "accounts"] | {"column": "account_id", "name": "jrc_sd_units_account_fk"} |
| add_foreign_key | ["jrc_service_desk_unit_memberships", "accounts"] | {"column": "account_id", "name": "jrc_sd_unit_memberships_account_fk"} |
| add_foreign_key | ["jrc_service_desk_ticket_statuses", "accounts"] | {"column": "account_id", "name": "jrc_sd_ticket_statuses_account_fk"} |
| add_foreign_key | ["jrc_service_desk_priorities", "accounts"] | {"column": "account_id", "name": "jrc_sd_priorities_account_fk"} |
| add_foreign_key | ["jrc_service_desk_categories", "accounts"] | {"column": "account_id", "name": "jrc_sd_categories_account_fk"} |
| add_foreign_key | ["jrc_service_desk_queues", "accounts"] | {"column": "account_id", "name": "jrc_sd_queues_account_fk"} |
| add_foreign_key | ["jrc_service_desk_tickets", "accounts"] | {"column": "account_id", "name": "jrc_sd_tickets_account_fk"} |
| add_foreign_key | ["jrc_service_desk_ticket_events", "accounts"] | {"column": "account_id", "name": "jrc_sd_ticket_events_account_fk"} |
| add_foreign_key | ["jrc_service_desk_ticket_notes", "accounts"] | {"column": "account_id", "name": "jrc_sd_ticket_notes_account_fk"} |
| add_foreign_key | ["jrc_service_desk_sla_snapshots", "accounts"] | {"column": "account_id", "name": "jrc_sd_sla_snapshots_account_fk"} |
| add_foreign_key | ["jrc_service_desk_sla_milestones", "accounts"] | {"column": "account_id", "name": "jrc_sd_sla_milestones_account_fk"} |
| add_foreign_key | ["jrc_service_desk_ticket_conversations", "accounts"] | {"column": "account_id", "name": "jrc_sd_ticket_conversations_account_fk"} |
| add_foreign_key | ["jrc_service_desk_unit_memberships", "jrc_service_desk_units"] | {"column": ["account_id", "unit_id"], "primary_key": ["account_id", "id"], "name": "jrc_sd_unit_memberships_unit_fk"} |
| add_foreign_key | ["jrc_service_desk_ticket_statuses", "jrc_service_desk_units"] | {"column": ["account_id", "unit_id"], "primary_key": ["account_id", "id"], "name": "jrc_sd_ticket_statuses_unit_fk"} |
| add_foreign_key | ["jrc_service_desk_priorities", "jrc_service_desk_units"] | {"column": ["account_id", "unit_id"], "primary_key": ["account_id", "id"], "name": "jrc_sd_priorities_unit_fk"} |
| add_foreign_key | ["jrc_service_desk_categories", "jrc_service_desk_units"] | {"column": ["account_id", "unit_id"], "primary_key": ["account_id", "id"], "name": "jrc_sd_categories_unit_fk"} |
| add_foreign_key | ["jrc_service_desk_queues", "jrc_service_desk_units"] | {"column": ["account_id", "unit_id"], "primary_key": ["account_id", "id"], "name": "jrc_sd_queues_unit_fk"} |
| add_foreign_key | ["jrc_service_desk_tickets", "jrc_service_desk_units"] | {"column": ["account_id", "unit_id"], "primary_key": ["account_id", "id"], "name": "jrc_sd_tickets_unit_fk"} |
| add_foreign_key | ["jrc_service_desk_ticket_events", "jrc_service_desk_units"] | {"column": ["account_id", "unit_id"], "primary_key": ["account_id", "id"], "name": "jrc_sd_ticket_events_unit_fk"} |
| add_foreign_key | ["jrc_service_desk_ticket_notes", "jrc_service_desk_units"] | {"column": ["account_id", "unit_id"], "primary_key": ["account_id", "id"], "name": "jrc_sd_ticket_notes_unit_fk"} |
| add_foreign_key | ["jrc_service_desk_sla_snapshots", "jrc_service_desk_units"] | {"column": ["account_id", "unit_id"], "primary_key": ["account_id", "id"], "name": "jrc_sd_sla_snapshots_unit_fk"} |
| add_foreign_key | ["jrc_service_desk_sla_milestones", "jrc_service_desk_units"] | {"column": ["account_id", "unit_id"], "primary_key": ["account_id", "id"], "name": "jrc_sd_sla_milestones_unit_fk"} |
| add_foreign_key | ["jrc_service_desk_ticket_conversations", "jrc_service_desk_units"] | {"column": ["account_id", "unit_id"], "primary_key": ["account_id", "id"], "name": "jrc_sd_ticket_conversations_unit_fk"} |
| add_foreign_key | ["jrc_service_desk_units", "jrc_service_desk_operator_companies"] | {"column": ["account_id", "operator_company_id"], "primary_key": ["account_id", "id"], "name": "jrc_sd_unit_operator_fk"} |
| add_foreign_key | ["jrc_service_desk_unit_memberships", "account_users"] | {"column": ["account_id", "account_user_id"], "primary_key": ["account_id", "id"], "name": "jrc_sd_membership_account_user_fk"} |
| add_foreign_key | ["jrc_service_desk_queues", "teams"] | {"column": ["account_id", "team_id"], "primary_key": ["account_id", "id"], "name": "jrc_sd_queue_team_fk"} |
| add_foreign_key | ["jrc_service_desk_tickets", "contacts"] | {"column": ["account_id", "requester_id"], "primary_key": ["account_id", "id"], "name": "jrc_sd_ticket_requester_fk"} |
| add_foreign_key | ["jrc_service_desk_tickets", "teams"] | {"column": ["account_id", "team_id"], "primary_key": ["account_id", "id"], "name": "jrc_sd_ticket_team_fk"} |
| add_foreign_key | ["jrc_service_desk_tickets", "jrc_service_desk_ticket_statuses"] | {"column": ["account_id", "unit_id", "status_id"], "primary_key": ["account_id", "unit_id", "id"], "name": "jrc_sd_ticket_status_id_fk"} |
| add_foreign_key | ["jrc_service_desk_tickets", "jrc_service_desk_priorities"] | {"column": ["account_id", "unit_id", "priority_id"], "primary_key": ["account_id", "unit_id", "id"], "name": "jrc_sd_ticket_priority_id_fk"} |
| add_foreign_key | ["jrc_service_desk_tickets", "jrc_service_desk_categories"] | {"column": ["account_id", "unit_id", "category_id"], "primary_key": ["account_id", "unit_id", "id"], "name": "jrc_sd_ticket_category_id_fk"} |
| add_foreign_key | ["jrc_service_desk_tickets", "jrc_service_desk_queues"] | {"column": ["account_id", "unit_id", "queue_id"], "primary_key": ["account_id", "unit_id", "id"], "name": "jrc_sd_ticket_queue_id_fk"} |
| add_foreign_key | ["jrc_service_desk_tickets", "jrc_service_desk_unit_memberships"] | {"column": ["account_id", "unit_id", "created_by_membership_id"], "primary_key": ["account_id", "unit_id", "id"], "name": "jrc_sd_ticket_creator_fk"} |
| add_foreign_key | ["jrc_service_desk_tickets", "jrc_service_desk_unit_memberships"] | {"column": ["account_id", "unit_id", "assignee_membership_id"], "primary_key": ["account_id", "unit_id", "id"], "name": "jrc_sd_ticket_assignee_fk"} |
| add_foreign_key | ["jrc_service_desk_ticket_events", "jrc_service_desk_tickets"] | {"column": ["account_id", "unit_id", "ticket_id"], "primary_key": ["account_id", "unit_id", "id"], "name": "jrc_sd_ticket_events_ticket_fk"} |
| add_foreign_key | ["jrc_service_desk_ticket_notes", "jrc_service_desk_tickets"] | {"column": ["account_id", "unit_id", "ticket_id"], "primary_key": ["account_id", "unit_id", "id"], "name": "jrc_sd_ticket_notes_ticket_fk"} |
| add_foreign_key | ["jrc_service_desk_sla_snapshots", "jrc_service_desk_tickets"] | {"column": ["account_id", "unit_id", "ticket_id"], "primary_key": ["account_id", "unit_id", "id"], "name": "jrc_sd_sla_snapshots_ticket_fk"} |
| add_foreign_key | ["jrc_service_desk_sla_milestones", "jrc_service_desk_tickets"] | {"column": ["account_id", "unit_id", "ticket_id"], "primary_key": ["account_id", "unit_id", "id"], "name": "jrc_sd_sla_milestones_ticket_fk"} |
| add_foreign_key | ["jrc_service_desk_ticket_conversations", "jrc_service_desk_tickets"] | {"column": ["account_id", "unit_id", "ticket_id"], "primary_key": ["account_id", "unit_id", "id"], "name": "jrc_sd_ticket_conversations_ticket_fk"} |
| add_foreign_key | ["jrc_service_desk_ticket_events", "jrc_service_desk_unit_memberships"] | {"column": ["account_id", "unit_id", "actor_membership_id"], "primary_key": ["account_id", "unit_id", "id"], "name": "jrc_sd_event_actor_fk"} |
| add_foreign_key | ["jrc_service_desk_ticket_notes", "jrc_service_desk_unit_memberships"] | {"column": ["account_id", "unit_id", "author_membership_id"], "primary_key": ["account_id", "unit_id", "id"], "name": "jrc_sd_note_author_fk"} |
| add_foreign_key | ["jrc_service_desk_ticket_conversations", "jrc_service_desk_unit_memberships"] | {"column": ["account_id", "unit_id", "linked_by_membership_id"], "primary_key": ["account_id", "unit_id", "id"], "name": "jrc_sd_conversation_actor_fk"} |
| add_foreign_key | ["jrc_service_desk_ticket_conversations", "conversations"] | {"column": ["account_id", "conversation_id"], "primary_key": ["account_id", "id"], "name": "jrc_sd_link_conversation_fk"} |
| add_foreign_key | ["jrc_service_desk_sla_milestones", "jrc_service_desk_sla_snapshots"] | {"column": ["account_id", "unit_id", "ticket_id", "sla_snapshot_id"], "primary_key": ["account_id", "unit_id", "ticket_id", "id"], "name": "jrc_sd_milestone_snapshot_fk"} |


## db/migrate/20260928120000_add_jrc_service_desk_lifecycle.rb

SHA-256: `5439b56d5940ddb37aa89718c12b35c986700429f626d39d62d88fde6562ab60`

### jrc_service_desk_services

| TIPO/DSL | COLUNA | OPCOES |
|---|---|---|
| integer | ["account_id"] | {"null": false} |
| bigint | ["unit_id"] | {"null": false} |
| string | ["name"] | {"null": false, "limit": 255} |
| string | ["code"] | {"null": false, "limit": 80} |
| boolean | ["active"] | {"null": false, "default": false} |
| timestamps | [] | {} |

### jrc_service_desk_lifecycle_policies

| TIPO/DSL | COLUNA | OPCOES |
|---|---|---|
| integer | ["account_id"] | {"null": false} |
| bigint | ["unit_id"] | {"null": false} |
| bigint | ["service_id"] | {} |
| string | ["name"] | {"null": false, "limit": 255} |
| boolean | ["enabled"] | {"null": false, "default": false} |
| bigint | ["current_version_id"] | {} |
| integer | ["lock_version"] | {"null": false, "default": 0} |
| timestamps | [] | {} |

### jrc_service_desk_lifecycle_policy_versions

| TIPO/DSL | COLUNA | OPCOES |
|---|---|---|
| integer | ["account_id"] | {"null": false} |
| bigint | ["unit_id"] | {"null": false} |
| bigint | ["lifecycle_policy_id"] | {"null": false} |
| bigint | ["actor_membership_id"] | {"null": false} |
| integer | ["version"] | {"null": false} |
| jsonb | ["definition"] | {"null": false} |
| jsonb | ["status_phases"] | {"null": false} |
| jsonb | ["publication"] | {"null": false} |
| string | ["digest"] | {"null": false, "limit": 64} |
| datetime | ["created_at"] | {"null": false} |

### jrc_service_desk_lifecycle_transitions

| TIPO/DSL | COLUNA | OPCOES |
|---|---|---|
| integer | ["account_id"] | {"null": false} |
| bigint | ["unit_id"] | {"null": false} |
| bigint | ["ticket_id"] | {"null": false} |
| bigint | ["lifecycle_policy_version_id"] | {"null": false} |
| bigint | ["actor_membership_id"] | {"null": false} |
| bigint | ["from_status_id"] | {"null": false} |
| bigint | ["to_status_id"] | {"null": false} |
| string | ["action"] | {"null": false, "limit": 32} |
| string | ["rule_key"] | {"null": false, "limit": 80} |
| string | ["request_key"] | {"null": false, "limit": 120} |
| string | ["fingerprint"] | {"null": false, "limit": 64} |
| datetime | ["occurred_at"] | {"null": false} |
| jsonb | ["payload"] | {"null": false} |
| datetime | ["created_at"] | {"null": false} |

### jrc_service_desk_sla_cycles

| TIPO/DSL | COLUNA | OPCOES |
|---|---|---|
| integer | ["account_id"] | {"null": false} |
| bigint | ["unit_id"] | {"null": false} |
| bigint | ["ticket_id"] | {"null": false} |
| bigint | ["lifecycle_policy_version_id"] | {"null": false} |
| bigint | ["sla_snapshot_id"] | {"null": false} |
| integer | ["number"] | {"null": false} |
| datetime | ["started_at"] | {"null": false} |
| timestamps | [] | {} |

### jrc_service_desk_sla_clocks

| TIPO/DSL | COLUNA | OPCOES |
|---|---|---|
| integer | ["account_id"] | {"null": false} |
| bigint | ["unit_id"] | {"null": false} |
| bigint | ["ticket_id"] | {"null": false} |
| bigint | ["sla_cycle_id"] | {"null": false} |
| string | ["kind"] | {"null": false, "limit": 24} |
| string | ["state"] | {"null": false, "limit": 24} |
| bigint | ["budget_seconds"] | {"null": false} |
| decimal | ["elapsed_seconds"] | {"null": false, "precision": 20, "scale": 6} |
| datetime | ["anchor_at"] | {"null": false} |
| datetime | ["due_at"] | {"null": false} |
| datetime | ["achieved_at"] | {} |
| string | ["calculator_version"] | {"null": false, "limit": 100} |
| integer | ["lock_version"] | {"null": false, "default": 0} |
| timestamps | [] | {} |

### jrc_service_desk_lifecycle_pauses

| TIPO/DSL | COLUNA | OPCOES |
|---|---|---|
| integer | ["account_id"] | {"null": false} |
| bigint | ["unit_id"] | {"null": false} |
| bigint | ["ticket_id"] | {"null": false} |
| bigint | ["lifecycle_policy_version_id"] | {"null": false} |
| bigint | ["sla_cycle_id"] | {} |
| bigint | ["started_by_membership_id"] | {"null": false} |
| bigint | ["ended_by_membership_id"] | {} |
| string | ["reason_code"] | {"null": false, "limit": 80} |
| jsonb | ["clocks"] | {"null": false} |
| datetime | ["started_at"] | {"null": false} |
| datetime | ["ended_at"] | {} |
| integer | ["lock_version"] | {"null": false, "default": 0} |
| timestamps | [] | {} |

### FKs / indices / checks

| ACAO | ALVO/COLUNAS | DEFINICAO |
|---|---|---|
| add_index | ["jrc_service_desk_services", ["account_id", "unit_id", "id"]] | {"unique": true, "name": "jrc_sd_lc_services_ref"} |
| add_index | ["jrc_service_desk_services", ["account_id", "unit_id", "code"]] | {"unique": true, "name": "jrc_sd_lc_service_code"} |
| add_check_constraint | ["jrc_service_desk_services", "btrim(name) <> '' AND btrim(code) <> ''"] | {"name": "jrc_sd_lc_service_names"} |
| add_index | ["jrc_service_desk_lifecycle_policies", ["account_id", "unit_id", "id"]] | {"unique": true, "name": "jrc_sd_lc_lifecycle_policies_ref"} |
| add_index | ["jrc_service_desk_lifecycle_policies", ["account_id", "unit_id"]] | {"unique": true, "where": "service_id IS NULL", "name": "jrc_sd_lc_unit_policy"} |
| add_index | ["jrc_service_desk_lifecycle_policies", ["account_id", "unit_id", "service_id"]] | {"unique": true, "where": "service_id IS NOT NULL", "name": "jrc_sd_lc_service_policy"} |
| add_index | ["jrc_service_desk_lifecycle_policy_versions", ["account_id", "unit_id", "id"]] | {"unique": true, "name": "jrc_sd_lc_lifecycle_policy_versions_ref"} |
| add_index | ["jrc_service_desk_lifecycle_policy_versions", ["account_id", "unit_id", "lifecycle_policy_id", "id"]] | {"unique": true, "name": "jrc_sd_lc_version_parent_ref"} |
| add_index | ["jrc_service_desk_lifecycle_policy_versions", ["lifecycle_policy_id", "version"]] | {"unique": true, "name": "jrc_sd_lc_version_number"} |
| add_check_constraint | ["jrc_service_desk_lifecycle_policy_versions", "version > 0 AND jsonb_typeof(definition) = 'object' AND digest ~ '^[a-f0-9]{64}$'"] | {"name": "jrc_sd_lc_version_valid"} |
| add_index | ["jrc_service_desk_lifecycle_transitions", ["account_id", "unit_id", "ticket_id", "id"]] | {"unique": true, "name": "jrc_sd_lc_lifecycle_transitions_ref"} |
| add_index | ["jrc_service_desk_lifecycle_transitions", ["account_id", "unit_id", "ticket_id", "actor_membership_id", "request_key"]] | {"unique": true, "name": "jrc_sd_lc_transition_key"} |
| add_index | ["jrc_service_desk_lifecycle_transitions", ["account_id", "unit_id", "ticket_id", "occurred_at", "id"]] | {"name": "jrc_sd_lc_transition_timeline"} |
| add_check_constraint | ["jrc_service_desk_lifecycle_transitions", "action IN ('pause','resume','resolve','close','cancel','reopen','work_status') AND jsonb_typeof(payload) = 'object' AND fingerprint ~ '^[a-f0-9]{64}$' AND btrim(request_key) <> ''"] | {"name": "jrc_sd_lc_transition_valid"} |
| add_index | ["jrc_service_desk_sla_cycles", ["account_id", "unit_id", "ticket_id", "id"]] | {"unique": true, "name": "jrc_sd_lc_sla_cycles_ref"} |
| add_index | ["jrc_service_desk_sla_cycles", ["account_id", "unit_id", "ticket_id", "number"]] | {"unique": true, "name": "jrc_sd_lc_cycle_number"} |
| add_check_constraint | ["jrc_service_desk_sla_cycles", "number > 0"] | {"name": "jrc_sd_lc_cycle_number_valid"} |
| add_index | ["jrc_service_desk_sla_clocks", ["account_id", "unit_id", "ticket_id", "id"]] | {"unique": true, "name": "jrc_sd_lc_sla_clocks_ref"} |
| add_index | ["jrc_service_desk_sla_clocks", ["account_id", "unit_id", "ticket_id", "sla_cycle_id", "kind"]] | {"unique": true, "name": "jrc_sd_lc_clock_kind"} |
| add_check_constraint | ["jrc_service_desk_sla_clocks", "kind IN ('first_response','resolution') AND state IN ('running','paused','completed','stopped') AND budget_seconds > 0 AND elapsed_seconds >= 0"] | {"name": "jrc_sd_lc_clock_values"} |
| add_check_constraint | ["jrc_service_desk_sla_clocks", "(state = 'completed') = (achieved_at IS NOT NULL)"] | {"name": "jrc_sd_lc_clock_completion"} |
| add_index | ["jrc_service_desk_lifecycle_pauses", ["account_id", "unit_id", "ticket_id", "id"]] | {"unique": true, "name": "jrc_sd_lc_lifecycle_pauses_ref"} |
| add_index | ["jrc_service_desk_lifecycle_pauses", ["account_id", "unit_id", "ticket_id"]] | {"unique": true, "where": "ended_at IS NULL", "name": "jrc_sd_lc_one_pause"} |
| add_check_constraint | ["jrc_service_desk_lifecycle_pauses", "jsonb_typeof(clocks) = 'array' AND clocks <@ '[\"first_response\",\"resolution\"]'::jsonb AND ((ended_at IS NULL) = (ended_by_membership_id IS NULL)) AND (ended_at IS NULL OR ended_at >= started_at)"] | {"name": "jrc_sd_lc_pause_period"} |
| add_foreign_key | ["jrc_service_desk_services", "accounts"] | {"column": "account_id"} |
| add_foreign_key | ["jrc_service_desk_services", "jrc_service_desk_units"] | {"column": ["account_id", "unit_id"], "primary_key": ["account_id", "id"], "name": "jrc_sd_lc_8c1eac17a78786f3d5fd_fk"} |
| add_foreign_key | ["jrc_service_desk_lifecycle_policies", "accounts"] | {"column": "account_id"} |
| add_foreign_key | ["jrc_service_desk_lifecycle_policies", "jrc_service_desk_units"] | {"column": ["account_id", "unit_id"], "primary_key": ["account_id", "id"], "name": "jrc_sd_lc_5d4b2ae138d6dcd2d563_fk"} |
| add_foreign_key | ["jrc_service_desk_lifecycle_policy_versions", "accounts"] | {"column": "account_id"} |
| add_foreign_key | ["jrc_service_desk_lifecycle_policy_versions", "jrc_service_desk_units"] | {"column": ["account_id", "unit_id"], "primary_key": ["account_id", "id"], "name": "jrc_sd_lc_6700244cad9d84f9270b_fk"} |
| add_foreign_key | ["jrc_service_desk_lifecycle_transitions", "accounts"] | {"column": "account_id"} |
| add_foreign_key | ["jrc_service_desk_lifecycle_transitions", "jrc_service_desk_units"] | {"column": ["account_id", "unit_id"], "primary_key": ["account_id", "id"], "name": "jrc_sd_lc_93886a9d959a412d8ee6_fk"} |
| add_foreign_key | ["jrc_service_desk_sla_cycles", "accounts"] | {"column": "account_id"} |
| add_foreign_key | ["jrc_service_desk_sla_cycles", "jrc_service_desk_units"] | {"column": ["account_id", "unit_id"], "primary_key": ["account_id", "id"], "name": "jrc_sd_lc_86dbb9b833bafac0ff2c_fk"} |
| add_foreign_key | ["jrc_service_desk_sla_clocks", "accounts"] | {"column": "account_id"} |
| add_foreign_key | ["jrc_service_desk_sla_clocks", "jrc_service_desk_units"] | {"column": ["account_id", "unit_id"], "primary_key": ["account_id", "id"], "name": "jrc_sd_lc_53e89155e366e94dc6ea_fk"} |
| add_foreign_key | ["jrc_service_desk_lifecycle_pauses", "accounts"] | {"column": "account_id"} |
| add_foreign_key | ["jrc_service_desk_lifecycle_pauses", "jrc_service_desk_units"] | {"column": ["account_id", "unit_id"], "primary_key": ["account_id", "id"], "name": "jrc_sd_lc_e5cde32ed282f4f277d6_fk"} |
| add_foreign_key | ["jrc_service_desk_lifecycle_policies", "jrc_service_desk_services"] | {"column": ["account_id", "unit_id", "service_id"], "primary_key": ["account_id", "unit_id", "id"], "name": "jrc_sd_lc_9583cbc86336d1b68f5e_fk"} |
| add_foreign_key | ["jrc_service_desk_lifecycle_policy_versions", "jrc_service_desk_lifecycle_policies"] | {"column": ["account_id", "unit_id", "lifecycle_policy_id"], "primary_key": ["account_id", "unit_id", "id"], "name": "jrc_sd_lc_82a0f9e91538d7ad5e44_fk"} |
| add_foreign_key | ["jrc_service_desk_lifecycle_policy_versions", "jrc_service_desk_unit_memberships"] | {"column": ["account_id", "unit_id", "actor_membership_id"], "primary_key": ["account_id", "unit_id", "id"], "name": "jrc_sd_lc_783f21fc0d62b0dcda5d_fk"} |
| add_foreign_key | ["jrc_service_desk_lifecycle_policies", "jrc_service_desk_lifecycle_policy_versions"] | {"column": ["account_id", "unit_id", "id", "current_version_id"], "primary_key": ["account_id", "unit_id", "lifecycle_policy_id", "id"], "name": "jrc_sd_lc_current_version_fk"} |
| add_foreign_key | ["jrc_service_desk_lifecycle_transitions", "jrc_service_desk_tickets"] | {"column": ["account_id", "unit_id", "ticket_id"], "primary_key": ["account_id", "unit_id", "id"], "name": "jrc_sd_lc_cf77431d460edbc54836_fk"} |
| add_foreign_key | ["jrc_service_desk_lifecycle_transitions", "jrc_service_desk_lifecycle_policy_versions"] | {"column": ["account_id", "unit_id", "lifecycle_policy_version_id"], "primary_key": ["account_id", "unit_id", "id"], "name": "jrc_sd_lc_1cb64e7b5fdba16b37ef_fk"} |
| add_foreign_key | ["jrc_service_desk_sla_cycles", "jrc_service_desk_tickets"] | {"column": ["account_id", "unit_id", "ticket_id"], "primary_key": ["account_id", "unit_id", "id"], "name": "jrc_sd_lc_ece94b547cf313d03248_fk"} |
| add_foreign_key | ["jrc_service_desk_sla_cycles", "jrc_service_desk_lifecycle_policy_versions"] | {"column": ["account_id", "unit_id", "lifecycle_policy_version_id"], "primary_key": ["account_id", "unit_id", "id"], "name": "jrc_sd_lc_be09fbe5e539aae7890e_fk"} |
| add_foreign_key | ["jrc_service_desk_lifecycle_pauses", "jrc_service_desk_tickets"] | {"column": ["account_id", "unit_id", "ticket_id"], "primary_key": ["account_id", "unit_id", "id"], "name": "jrc_sd_lc_244ef841e81d2d71d0c1_fk"} |
| add_foreign_key | ["jrc_service_desk_lifecycle_pauses", "jrc_service_desk_lifecycle_policy_versions"] | {"column": ["account_id", "unit_id", "lifecycle_policy_version_id"], "primary_key": ["account_id", "unit_id", "id"], "name": "jrc_sd_lc_ff94180ace6ba8957c3c_fk"} |
| add_foreign_key | ["jrc_service_desk_lifecycle_transitions", "jrc_service_desk_unit_memberships"] | {"column": ["account_id", "unit_id", "actor_membership_id"], "primary_key": ["account_id", "unit_id", "id"], "name": "jrc_sd_lc_2975db347397ce297cec_fk"} |
| add_foreign_key | ["jrc_service_desk_lifecycle_transitions", "jrc_service_desk_ticket_statuses"] | {"column": ["account_id", "unit_id", "from_status_id"], "primary_key": ["account_id", "unit_id", "id"], "name": "jrc_sd_lc_6d97861e11981c6a6095_fk"} |
| add_foreign_key | ["jrc_service_desk_lifecycle_transitions", "jrc_service_desk_ticket_statuses"] | {"column": ["account_id", "unit_id", "to_status_id"], "primary_key": ["account_id", "unit_id", "id"], "name": "jrc_sd_lc_d0b7f293ace9b0865991_fk"} |
| add_foreign_key | ["jrc_service_desk_sla_cycles", "jrc_service_desk_sla_snapshots"] | {"column": ["account_id", "unit_id", "ticket_id", "sla_snapshot_id"], "primary_key": ["account_id", "unit_id", "ticket_id", "id"], "name": "jrc_sd_lc_57795d1c18d31cc851cc_fk"} |
| add_foreign_key | ["jrc_service_desk_sla_clocks", "jrc_service_desk_sla_cycles"] | {"column": ["account_id", "unit_id", "ticket_id", "sla_cycle_id"], "primary_key": ["account_id", "unit_id", "ticket_id", "id"], "name": "jrc_sd_lc_6785476a9d1ed7010fcd_fk"} |
| add_foreign_key | ["jrc_service_desk_lifecycle_pauses", "jrc_service_desk_sla_cycles"] | {"column": ["account_id", "unit_id", "ticket_id", "sla_cycle_id"], "primary_key": ["account_id", "unit_id", "ticket_id", "id"], "name": "jrc_sd_lc_2eed46e90db61ccb1a49_fk"} |
| add_foreign_key | ["jrc_service_desk_lifecycle_pauses", "jrc_service_desk_unit_memberships"] | {"column": ["account_id", "unit_id", "started_by_membership_id"], "primary_key": ["account_id", "unit_id", "id"], "name": "jrc_sd_lc_4abfeb5e9c1e55ad9272_fk"} |
| add_foreign_key | ["jrc_service_desk_lifecycle_pauses", "jrc_service_desk_unit_memberships"] | {"column": ["account_id", "unit_id", "ended_by_membership_id"], "primary_key": ["account_id", "unit_id", "id"], "name": "jrc_sd_lc_a0322dd34d8501041c7e_fk"} |
| add_column | ["jrc_service_desk_tickets", "service_id", "bigint"] | {} |
| add_column | ["jrc_service_desk_tickets", "lifecycle_policy_version_id", "bigint"] | {} |
| add_index | ["jrc_service_desk_tickets", ["account_id", "unit_id", "service_id"]] | {"name": "jrc_sd_ticket_service"} |
| add_index | ["jrc_service_desk_tickets", ["account_id", "unit_id", "lifecycle_policy_version_id"]] | {"name": "jrc_sd_ticket_lc_version"} |
| add_foreign_key | ["jrc_service_desk_tickets", "jrc_service_desk_services"] | {"column": ["account_id", "unit_id", "service_id"], "primary_key": ["account_id", "unit_id", "id"], "name": "jrc_sd_lc_494d58616d7e06366570_fk"} |
| add_foreign_key | ["jrc_service_desk_tickets", "jrc_service_desk_lifecycle_policy_versions"] | {"column": ["account_id", "unit_id", "lifecycle_policy_version_id"], "primary_key": ["account_id", "unit_id", "id"], "name": "jrc_sd_lc_8474edf85fdbbeae3b72_fk"} |
