# CP2 - inventario nativo da baseline consolidada

Este inventario descreve arquivos efetivamente lidos do ZIP com SHA confirmado, nao o
servidor do usuario nem versoes anteriores. Somente a baseline consolidada e fonte do codigo.
Nenhuma biblioteca externa, versao atual de framework ou arquitetura auxiliar foi usada
para substituir o que existe no projeto. Recomendacoes aparecem como tais.

## Sintese dos padroes observados

| Tema | Padrao observado | Consequencia para o futuro CP2 |
|---|---|---|
| account_id | Account e tenant; pertence via belongs_to e consultas por account. User pertence por AccountUser. | Contexto autenticado + escopo, nao params como prova. |
| IDs | Accounts/users/contacts/conversations usam serial; entidades novas como Team/AccountUser/Company/CRM usam bigint. Conversation tambem tem uuid e display_id distintos. | Reutilizar tipos conforme alvo; nao migrar IDs globais nem confundir display_id com id. |
| FKs | Migrations Rails 7.0/7.1, references e add_foreign_key, on_delete variavel por dominio. | Nao copiar cascades indiscriminadamente; dados auditaveis precisam de ciclo de vida documentado. |
| Conta de referencia | Alguns models fazem validacao explicita por Account. FKs inspecionadas sao simples; schema nao declara FK composta. | Projetar consistencia de relacoes e testa-la tambem sem validacoes de model; uma FK simples so verifica existencia. |
| Indices | Simples, compostos e parciais; por Account, status, responsavel, chave/versao ou idempotencia. | Escolher pelo acesso real e unicidade; Account no prefixo quando a consulta e por conta. |
| Timestamps | Novas migrations usam t.timestamps; schema legado mistura precision:nil; auditoria CRM tem created_at apenas. | Padrao por natureza do dado, sem normalizacao global. |
| Enums | Conversation usa integer; Deal usa string; etapas comerciais sao configuracao persistida. | Separar estado tecnico e configuracao; nao copiar os estados de outro modulo. |
| Soft delete | Sales usa archived_at, CRM usa status archived/active. Nao encontrado mecanismo universal nos paths revisados. | Nao acrescentar biblioteca ou default_scope global; arquivamento nao equivale a apagar historico. |
| Auditoria | Gem audited e concerns Enterprise; audit events especificos no CRM. | Reaproveitar mecanismos compativeis; historico SD nao deve alterar lista de eventos do CRM. |
| Models | ApplicationRecord e bases de namespace. Base CP1 ja esta pronta e abstrata. | Herdar JrcServiceDesk::Base e preservar validacao generica de tamanhos. |
| Services | Classes com call, transacoes, with_lock, lock_version em dados e idempotencia em alguns fluxos. | Seguir os mecanismos quando necessarios, nao framework paralelo. |
| Policies | Pundit com user_context contendo user/account/account_user. Base CP1 nega. | Cada autorizacao futura e a intersecao de conta, escopo e acao. |
| Storage | Active Storage polimorfico; Attachment nativo exige Message. | Nao duplicar blobs nem tornar URL assinada prova de permissao. |
| Equipes | Team de Account; TeamMember vincula User. | Reutilizar pessoas/equipes, mas nao inventar que isso concede acesso a unidade. |

## Achados que nao resolvem as duas decisoes

A busca nos models/services/policies, extensoes de models e schema nao encontrou cadastro
multioperadora/unidade pronto. A referencia `operator_company_id` em NICO foi analisada:
uma configuracao externa por Account, com string de identificador, nao armazena varias
operadoras/unidades nem memberships. Isso nao autoriza reutiliza-la como estrutura do SD.

As permissoes nativas possuem papeis base e CustomRole; nao foi encontrado o mapeamento
AccountUser/Team para unidade operacional requerido para CP2. Ausencia do mapeamento nao
justifica criar RBAC paralelo ou liberar todos os dados para administrador.

## Evidencias locais (numeros de linha da baseline)

Os trechos abaixo incluem SHA-256 do arquivo completo. Sao evidencia estatica, nao execucao
Rails, SQL ou verificacao do comportamento no ambiente de destino.

### Account e contexto

Account e localizado e o helper verifica AccountUser antes de construir Current. Params nao bastam.

`app/controllers/concerns/ensure_current_account_helper.rb:L23-L35`

SHA-256: `b9bcda2ef09908d5269e0b5e46eb2aba260299af4a2b3035ccc6e500bc0f4149`

```text
23:   def account_accessible_for_user?(account)
24:     @current_account_user = account.account_users.find_by(user_id: current_user.id)
25:     Current.account_user = @current_account_user
26:     render_unauthorized(I18n.t('errors.account.not_authorized')) unless @current_account_user
27:   end
28:
29:   def account_accessible_for_bot?(account)
30:     return if @resource.account_id == account.id
31:     return if @resource.agent_bot_inboxes.find_by(account_id: account.id)
32:
33:     render_unauthorized('Bot is not authorized to access this account')
34:   end
35: end
```

### Pundit nativo

O contexto de Pundit e o contrato a reutilizar; nao outro sistema de sessao.

`app/controllers/application_controller.rb:L21-L28`

SHA-256: `a994663b023a141c2a8b27b6868e9de830beb3b6b5bb9694ffb9d51b604189bf`

```text
21:   def pundit_user
22:     {
23:       user: Current.user,
24:       account: Current.account,
25:       account_user: Current.account_user
26:     }
27:   end
28: end
```

### Base CP1

Base abstrata ja possui belongs_to :account obrigatorio; nao criar outra base.

`app/models/jrc_service_desk/base.rb:L4-L8`

SHA-256: `dd11d622813bf53d5aa8882f4505fec01c48ce6f97abc3774700bb3d6624b0ea`

```text
4: class JrcServiceDesk::Base < ApplicationRecord
5:   self.abstract_class = true
6:
7:   belongs_to :account, optional: false
8: end
```

### Contexto CP1

Disponibilidade requer conta/usuario/vinculo persistidos, conta ativa e flag; nao concede uma acao.

`app/services/jrc_service_desk/access_context.rb:L15-L26`

SHA-256: `299d87b382f3120d82bbede4e936a1bf68407009f738a6078a58906751e84ed4`

```text
15:   def available?
16:     return false unless account && user && account_user
17:     return false unless account.persisted? && user.persisted? && account_user.persisted?
18:     return false unless account.id && user.id
19:     return false unless account_user.account_id == account.id && account_user.user_id == user.id
20:
21:     account.active? && account.feature_enabled?(::JrcServiceDesk::FEATURE_FLAG) == true
22:   end
23:
24:   # Even a matching account never grants an action without a concrete policy.
25:   def record_in_account?(record)
26:     available? && record.respond_to?(:account_id) && record.account_id == account.id
```

### Policy CP1

Base nega show e scope.resolve; demais acoes negativas herdadas de ApplicationPolicy.

`app/policies/jrc_service_desk/base_policy.rb:L5-L32`

SHA-256: `c62caabbd87a3bcf2446671e03d51f0ef17cf2b339f0ae01efd5af69cebdcf5a`

```text
5: class JrcServiceDesk::BasePolicy < ApplicationPolicy
6:   # ApplicationPolicy#show? delegates to a scope. The foundation must deny it too.
7:   def show?
8:     false
9:   end
10:
11:   protected
12:
13:   def service_desk_context
14:     @service_desk_context ||= ::JrcServiceDesk::AccessContext.new(user_context)
15:   end
16:
17:   class Scope < ApplicationPolicy::Scope
18:     def resolve
19:       scope.none
20:     end
21:
22:     protected
23:
24:     # A tenant boundary, not the final authorized scope. Concrete scopes MUST
25:     # also apply the approved company/unit/team/queue/record authorization.
26:     def account_scope
27:       context = ::JrcServiceDesk::AccessContext.new(user_context)
28:       return scope.none unless context.available?
29:
30:       scope.where(account_id: context.account.id)
31:     end
32:   end
```

### IDs legados

Account tem PK serial; contas nao sao UUIDs.

`db/schema.rb:L63-L76`

SHA-256: `1d0bed42ed46342ce76900fd176199e189e0de84092856bd171b6ade581ec147`

```text
63:   create_table "accounts", id: :serial, force: :cascade do |t|
64:     t.string "name", null: false
65:     t.datetime "created_at", precision: nil, null: false
66:     t.datetime "updated_at", precision: nil, null: false
67:     t.integer "locale", default: 0
68:     t.string "domain", limit: 100
69:     t.string "support_email", limit: 100
70:     t.bigint "feature_flags", default: 0, null: false
71:     t.integer "auto_resolve_duration"
72:     t.jsonb "limits", default: {}
73:     t.jsonb "custom_attributes", default: {}
74:     t.integer "status", default: 0
75:     t.jsonb "internal_attributes", default: {}, null: false
76:     t.jsonb "settings", default: {}
```

### Usuarios e perten ca

User e global; perten ca vem de AccountUser. Papeis base agent=0/administrator=1.

`app/models/account_user.rb:L28-L39`

SHA-256: `3c08c37c2c79a0e4a3ab713238ce1426ee2129edc4b557528fa3dfe1b19aeb50`

```text
28: class AccountUser < ApplicationRecord
29:   include AvailabilityStatusable
30:
31:   belongs_to :account
32:   belongs_to :user
33:   belongs_to :inviter, class_name: 'User', optional: true
34:
35:   enum role: { agent: 0, administrator: 1 }
36:   enum availability: { online: 0, offline: 1, busy: 2, meeting: 3, feedback: 4, end_shift: 5, training: 6, bathroom_break: 7, lunch_break: 8, manual_call: 9 }
37:
38:   accepts_nested_attributes_for :account
39:
```

### Permissoes nativas

Base permissions devolve papel e eventual jrc_crm; nao existem grants SD.

`app/models/account_user.rb:L59-L64`

SHA-256: `3c08c37c2c79a0e4a3ab713238ce1426ee2129edc4b557528fa3dfe1b19aeb50`

```text
59:   def permissions
60:     base_permissions = administrator? ? ['administrator'] : ['agent']
61:     base_permissions << 'jrc_crm' if account.feature_enabled?('jrc_crm')
62:     base_permissions
63:   end
64:
```

### CustomRole

Seis chaves aceitas; nenhuma de Service Desk. Nao confundir existencia do codigo Enterprise com disponibilidade no destino.

`enterprise/app/models/custom_role.rb:L34-L45`

SHA-256: `4c20705c8d2ba5170567d10bb02fb8c4dea8102b02e0dc8d030cc67ed6877422`

```text
34:   PERMISSIONS = %w[
35:     conversation_manage
36:     conversation_unassigned_manage
37:     conversation_participating_manage
38:     contact_manage
39:     report_manage
40:     knowledge_base_manage
41:   ].freeze
42:
43:   validates :name, presence: true
44:   validates :permissions, inclusion: { in: PERMISSIONS }
45:
```

### Extensao de AccountUser

CustomRole substitui a lista base de permissoes quando presente.

`enterprise/app/models/enterprise/account_user.rb:L2-L5`

SHA-256: `64823346d7be0422ea102a6d09bdd5f5a4c6fc63732522d0755bea9f70c52cc7`

```text
2:   def permissions
3:     custom_role.present? ? (custom_role.permissions + ['custom_role']) : super
4:   end
5: end
```

### Equipe

Team pertence a Account; nao representa empresa operadora/unidade.

`app/models/team.rb:L20-L29`

SHA-256: `1e3d09225441bf3ce2e7bec7d913d30519cdc760d59c5c29d0237caa1955ee58`

```text
20: class Team < ApplicationRecord
21:   include AccountCacheRevalidator
22:
23:   belongs_to :account
24:   has_many :team_members, dependent: :destroy_async
25:   has_many :members, through: :team_members, source: :user
26:   has_many :conversations, dependent: :nullify
27:   has_many :sales_opportunities, dependent: :nullify
28:
29:   before_destroy :capture_filtered_unread_count_member_ids, prepend: true
```

### Participacao em equipe

TeamMember liga User a Team; nao contem unidade operacional.

`app/models/team_member.rb:L17-L23`

SHA-256: `e0bf949855f8f037eca4b9e1e96dae26e1780d3f8463873fd77c90cb93b43867`

```text
17: class TeamMember < ApplicationRecord
18:   belongs_to :user
19:   belongs_to :team
20:   validates :user_id, uniqueness: { scope: :team_id }
21:
22:   after_commit :invalidate_filtered_unread_count_visibility, on: [:create, :destroy]
23:
```

### Cliente Company

Company relaciona contatos clientes; nao deve virar operadora.

`enterprise/app/models/company.rb:L38-L43`

SHA-256: `0cc8af31c40d631ca982235b17dae68bff07028f9a964b7b75dacb2106079274`

```text
38:   belongs_to :account
39:   has_many :contacts, dependent: :nullify
40:   before_validation :prepare_jsonb_attributes
41:   after_create_commit :fetch_favicon, if: -> { domain.present? }
42:   after_update_commit :enqueue_contact_company_name_sync, if: :saved_change_to_name?
43:
```

### Cliente CRM

CompanyAdapter resolve o tipo cliente; nao torna IDs de modelos distintos intercambiaveis.

`app/services/jrc_crm/company_adapter.rb:L26-L33`

SHA-256: `b85aecdddfb1e9a936c47690f0b722e1320317192f0e12e8e69626cbb4627f8f`

```text
26:     def self.resolve_entity(account:, organization_id: nil, company_id: nil)
27:       if organization_id.present?
28:         account.jrc_crm_organizations.find_by(id: organization_id)
29:       elsif company_id.present? && enterprise_company_available?(account)
30:         account.companies.find_by(id: company_id)
31:       else
32:         nil
33:       end
```

### Operadora em NICO

operator_company_id e configuracao externa string, nao cadastro operacional multiunidade.

`app/models/jrc_nico/erp_setting.rb:L21-L26`

SHA-256: `a0f732de892deea14a0671fe90bb7294df138b2d37e790f65d7bd8531cca25c5`

```text
21: class JrcNico::ErpSetting < ApplicationRecord
22:   self.table_name = 'jrc_nico_erp_settings'
23:   belongs_to :account
24:   validates :mode, inclusion: { in: %w[off fixture live] }
25:   validates :operator_company_id, :requester_user_id, format: { with: /\A[1-9]\d{0,12}\z/ }, allow_blank: true
26: end
```

### Referencias e indices

Exemplo de referencias tipadas, FKs e indices compostos/condicionais no dominio atual.

`db/migrate/20260824090000_create_sales_module.rb:L32-L73`

SHA-256: `3abefeee360de7c68355352025f934f05a4b0d0e5401655f3d1b05b392bd13ce`

```text
32:     create_table :sales_opportunities do |t|
33:       t.references :account, null: false, type: :integer, foreign_key: true
34:       t.references :sales_pipeline, null: false, foreign_key: true
35:       t.references :sales_stage, null: false, foreign_key: true
36:       t.references :contact, null: false, type: :integer, foreign_key: true
37:       t.references :conversation, type: :integer, foreign_key: true
38:       t.references :inbox, type: :integer, foreign_key: true
39:       t.references :team, foreign_key: true
40:       t.references :owner, null: false, type: :integer, foreign_key: { to_table: :users }
41:       t.references :loss_reason, foreign_key: { to_table: :sales_loss_reasons }
42:       t.string :title, null: false
43:       t.string :product_name
44:       t.decimal :value, precision: 15, scale: 2
45:       t.string :temperature, null: false, default: 'warm'
46:       t.string :source_channel
47:       t.string :status, null: false, default: 'open'
48:       t.text :notes
49:       t.text :loss_notes
50:       t.datetime :won_at
51:       t.datetime :lost_at
52:       t.datetime :archived_at
53:       t.string :idempotency_key
54:       t.timestamps
55:     end
56:     add_index :sales_opportunities, [:account_id, :owner_id]
57:     add_index :sales_opportunities, [:account_id, :contact_id]
58:     add_index :sales_opportunities, [:account_id, :conversation_id]
59:     add_index :sales_opportunities, [:account_id, :sales_stage_id]
60:     add_index :sales_opportunities, [:account_id, :status]
61:     add_index :sales_opportunities, [:account_id, :idempotency_key], unique: true,
62:               where: 'idempotency_key IS NOT NULL'
63:
64:     create_table :sales_activities do |t|
65:       t.references :account, null: false, type: :integer, foreign_key: true
66:       t.references :sales_opportunity, null: false, foreign_key: true
67:       t.references :contact, null: false, type: :integer, foreign_key: true
68:       t.references :owner, null: false, type: :integer, foreign_key: { to_table: :users }
69:       t.string :activity_type, null: false
70:       t.string :title, null: false
71:       t.datetime :scheduled_at, null: false
72:       t.string :status, null: false, default: 'scheduled'
73:       t.text :notes
```

### Integridade CRM

FKs simples por ID; existencia do alvo nao demonstra igualdade de account_id.

`db/migrate/20260824000016_add_jrc_crm_integrity_constraints.rb:L12-L19`

SHA-256: `2f353da81988d0287f02285a9111283369fe73710deba5d82d71d00f3c24377e`

```text
12:     add_foreign_key :jrc_crm_deals, :accounts
13:     add_foreign_key :jrc_crm_deals, :jrc_crm_pipelines, column: :pipeline_id
14:     add_foreign_key :jrc_crm_deals, :jrc_crm_stages, column: :stage_id
15:     add_foreign_key :jrc_crm_deals, :users, column: :owner_id
16:     add_foreign_key :jrc_crm_deals, :contacts
17:     add_foreign_key :jrc_crm_deals, :teams
18:     add_foreign_key :jrc_crm_deals, :jrc_crm_lost_reasons, column: :lost_reason_id
19:     add_foreign_key :jrc_crm_deals, :jrc_crm_leads, column: :lead_id
```

### Associacoes da mesma conta

Model valida algumas associacoes; nao copiar presumindo cobertura de toda referencia nova.

`app/models/jrc_crm/deal.rb:L152-L160`

SHA-256: `3278604d0a29fc4b8069b291934767f486ac96ad82a28919faf8e82455872455`

```text
152:     def associations_belong_to_account
153:       errors.add(:pipeline, 'must belong to account') if pipeline && pipeline.account_id != account_id
154:       errors.add(:stage, 'must belong to account') if stage && (stage.account_id != account_id || stage.pipeline_id != pipeline_id)
155:       errors.add(:owner, 'must belong to account') if owner && !account.users.exists?(owner.id)
156:       errors.add(:team, 'must belong to account') if team && team.account_id != account_id
157:       errors.add(:contact, 'must belong to account') if contact && contact.account_id != account_id
158:       errors.add(:lost_reason, 'must belong to account') if lost_reason && lost_reason.account_id != account_id
159:     end
160:
```

### Enum tecnico

Status/prioridade de Conversas sao enums inteiros, preservados. CRM tambem usa enums string.

`app/models/conversation.rb:L83-L85`

SHA-256: `dd70089bab6c01e623108a36116ef2955096ed478c03a8e662a3181048cdd5d4`

```text
83:   enum status: { open: 0, resolved: 1, pending: 2, snoozed: 3 }
84:   enum priority: { low: 0, medium: 1, high: 2, urgent: 3 }
85:
```

### Configuracao persistida

Etapas configuraveis, active e timestamps coexistem com enums tecnicos.

`db/migrate/20260824000001_create_jrc_crm_pipelines_and_stages.rb:L14-L33`

SHA-256: `4b3322b17c1fc5532ca4eea1f78810434edc4b1a39f37372e0d8197fe41749a3`

```text
14:     create_table :jrc_crm_stages do |t|
15:       t.integer :account_id, null: false
16:       t.bigint :pipeline_id, null: false
17:       t.string :name, null: false
18:       t.string :key, null: false
19:       t.integer :position, null: false
20:       t.string :color
21:       t.decimal :probability, precision: 5, scale: 2
22:       t.boolean :is_terminal, default: false, null: false
23:       t.boolean :is_won, default: false, null: false
24:       t.boolean :is_lost, default: false, null: false
25:       t.boolean :requires_handoff, default: false, null: false
26:       t.boolean :active, default: true, null: false
27:       t.jsonb :settings, default: {}, null: false
28:       t.timestamps null: false
29:     end
30:     add_index :jrc_crm_stages, :account_id
31:     add_index :jrc_crm_stages, [:pipeline_id, :key], unique: true
32:   end
33: end
```

### Arquivamento

Existe archived_at no dominio Sales, nao gem/concern universal de soft delete.

`app/models/sales_opportunity.rb:L84-L86`

SHA-256: `b0b841e3ae26a1eb2e8821a3f2991629f0d3492f1ceb605f1d6e8bb164f0743f`

```text
84:   scope :active, -> { where(archived_at: nil) }
85:
86:   def next_activity
```

### Audited existente

Audited e integrado por concern Enterprise; nao ativar globalmente para resolver SD.

`enterprise/app/models/enterprise/audit/team.rb:L4-L7`

SHA-256: `036e7ca4d3f354fe330fc1e92ec43517a12f5fd9f86c43d39ff91aedd943b12e`

```text
4:   included do
5:     audited associated_with: :account
6:   end
7: end
```

### Historico por dominio

Evento CRM usa antes/depois JSONB e created_at; nao basta para garantir imutabilidade de SD.

`db/migrate/20260824000010_create_jrc_crm_audit_events.rb:L3-L22`

SHA-256: `e04c6df657898321f03af5094911c36929fdb42975fae374ac2b430993f5680d`

```text
3:     create_table :jrc_crm_audit_events do |t|
4:       t.integer :account_id, null: false
5:       t.string :event_type
6:       t.string :actor_type
7:       t.integer :actor_id
8:       t.string :resource_type
9:       t.bigint :resource_id
10:       t.jsonb :from_value
11:       t.jsonb :to_value
12:       t.jsonb :metadata
13:       t.string :ip_address
14:       t.datetime :created_at, null: false
15:     end
16:     add_index :jrc_crm_audit_events, :account_id
17:     add_index :jrc_crm_audit_events, :event_type
18:     add_index :jrc_crm_audit_events, [:resource_type, :resource_id]
19:     add_index :jrc_crm_audit_events, :actor_id
20:     add_index :jrc_crm_audit_events, :created_at
21:   end
22: end
```

### Falha de auditoria

Captura erro de auditoria e grava log; copiar isso para mutacao auditada precisa de avaliacao, nao pode significar sucesso sem evento.

`app/services/jrc_crm/audit_logger_service.rb:L27-L29`

SHA-256: `ef1af90f083be71288ece0d66b3e2f7b94aebf721f840442abeeecb4196cd0a4`

```text
27:     rescue StandardError => e
28:       Rails.logger.error("Failed to create audit event: #{e.message}")
29:     end
```

### Transacao e lock

Service existente usa transacao e with_lock; padrao reaproveitavel sem refatorar CRM.

`app/services/jrc_crm/lead_conversion_service.rb:L14-L32`

SHA-256: `f2dd16d74f89515fcb9c4f04e29d7a4c31f1b7451f74723e675cd58d240947de`

```text
14:     ActiveRecord::Base.transaction do
15:       @lead.with_lock do
16:         existing = existing_deal
17:         if existing
18:           success(existing, false)
19:         else
20:           contact = find_or_create_contact
21:           company = find_or_create_company
22:           deal = create_deal(contact, company)
23:           attach_product(deal)
24:           @lead.update!(status: 'converted', converted_at: Time.current, contact: contact)
25:           log_conversion(deal, contact, company)
26:           success(deal, true, contact, company&.dig(:record))
27:         end
28:       end
29:     end
30:   rescue ActiveRecord::RecordNotUnique
31:     success(@account.jrc_crm_deals.find_by!(conversion_key: conversion_key), false)
32:   rescue StandardError => e
```

### Active Storage

Attachment atual exige Message e tem has_one_attached :file; nao e documento generico do SD.

`app/models/attachment.rb:L41-L45`

SHA-256: `6f87dff0a8ca2df81e9c63a36393d9c5095c9efb638befe125754e8e1e616de4`

```text
41:   belongs_to :account
42:   belongs_to :message
43:   has_one_attached :file
44:   before_save :set_extension
45:   validate :acceptable_file
```

### Feature flags

Posicao calculada pela ordem dentro da coluna; preservar YAML e algoritmo.

`app/models/concerns/featurable.rb:L15-L31`

SHA-256: `ef0f95dcdb9a492b8bd17a280aee536e33c2aad9cfb61d015f9211095060d4ca`

```text
15:   def self.feature_flag_mappings_for(feature_list)
16:     features_by_column = feature_list.group_by { |feature| feature['column'].presence || DEFAULT_FEATURE_FLAG_COLUMN }
17:
18:     mappings = FEATURE_FLAG_COLUMNS.index_with do |column|
19:       features = features_by_column.delete(column) || []
20:       validate_feature_count!(column, features)
21:
22:       features.each_with_index.to_h do |feature, index|
23:         [index + 1, "feature_#{feature['name']}".to_sym]
24:       end
25:     end
26:
27:     validate_feature_columns!(features_by_column)
28:     mappings
29:   end
30:
31:   def self.validate_feature_count!(column, features)
```

### Flag SD

Default false e coluna ext_1; posicao verificada pelo inventario de YAML.

`config/features.yml:L283-L286`

SHA-256: `1a3a9bc50239abd49feb784f7b6981df8b366baee0f835c9ed162f99e4b6aad3`

```text
283: - name: jrc_service_desk
284:   display_name: JRC Service Desk
285:   enabled: false
286:   column: feature_flags_ext_1
```

### SLA Conversas

SlaPolicy ligado a conversations/applied_slas; SD nao deve reconfigura-lo.

`enterprise/app/models/sla_policy.rb:L20-L28`

SHA-256: `2b45873419044f70039bb1df967c7dddcbfc7b514765eb9abd5baab1a4771f65`

```text
20: class SlaPolicy < ApplicationRecord
21:   belongs_to :account
22:   validates :name, presence: true
23:
24:   has_many :conversations, dependent: :nullify
25:   has_many :applied_slas, dependent: :destroy_async
26:
27:   def push_event_data
28:     {
```

### Teste nativo de conta

RSpec com registro de outra Account; ponto de partida dos testes futuros, nao teste CP2 executado.

`spec/models/jrc_crm/deal_spec.rb:L11-L17`

SHA-256: `c1cf746e1fd79bddfb00f52902835fc6b52a98c59e908898dd141a42f3d2e746`

```text
11:   it 'rejects associations from another account' do
12:     foreign_contact = create(:contact, account: create(:account))
13:     deal = described_class.new(account: account, pipeline: pipeline, stage: stage, owner: owner,
14:                                contact: foreign_contact, title: 'Teste', value_cents: 0)
15:
16:     expect(deal).not_to be_valid
17:     expect(deal.errors[:contact]).to be_present
```
