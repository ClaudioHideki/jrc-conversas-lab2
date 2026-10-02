# Auditoria diferencial PREVIA - Cadastro Mestre na base 80f7305

Data: 02/10/2026. Auditoria estatica; nenhum banco, servidor, migration ou Docker executado.

## Fontes conferidas

- official: `JRC-CONVERSAS-ULTIMA-ATUALIZACAO-80f7305-20261002.zip`; SHA-256 `69717c07f0143304ee2ec7e8983851d6caf58b0963d630b199b97f9c4819c5f4`; 10184 arquivos; 82749155 bytes. CRC de todas as entradas valido.

- reference: `JRC-CONVERSAS-CADASTRO-MESTRE-CANDIDATO-20261002.zip`; SHA-256 `9bb22e9a16ac9c122d0697cde207baf8389d541559a4b6c4ce34dad7ea8734c9`; 9468 arquivos; 81828322 bytes. CRC de todas as entradas valido.

- ancestor: `jrc-conversas-nico-v12-2-7-comercial-integrado-main (5).zip`; SHA-256 `0e8d7e18e244ffef0e045d5c14428f2bc6702dacb9c4d508236a7fa292a1f7c4`; 9394 arquivos; 81947752 bytes. CRC de todas as entradas valido.

## Resultado e cuidado com finais de linha
A base oficial tem 790 arquivos ausentes no candidato. O candidato tem 74 ausentes na oficial. Entre arquivos comuns, 9179 diferem por bytes e 215 sao identicos.
A comparacao com a ancestral usada no candidato mostra que 9021 mudancas da oficial sao somente LF/CRLF; ha 158 alteracoes substantivas e 790 adicoes oficiais. Os bytes originais de arquivos nao tocados serao mantidos, sem normalizar o projeto inteiro.
O candidato anterior adicionou 74 arquivos e modificou 35. Desses 35, 17 tambem receberam alteracoes substantivas na oficial. Todos os 35 serao revisados por diff de tres vias; nenhuma copia completa de diretorios da referencia sera aplicada.

## Mapa e decisoes antes do porte
- `companies` continua a tabela empresarial nativa; preservar IDs, `domain`, atributos JSON e recursos Enterprise. O adapter `JrcCustomers::Company` acessara ESTA tabela, nao uma tabela nova.
- `Contact`/`ContactInbox`, conversas e identificadores de canais permanecem nativos. Dados complementares e empresa ficam no mesmo contato. Nao reescrever protocolos.
- `JrcCrm::Organization` permanece legado, com company_id mapeado explicitamente; nomes nao autorizam merge. Preservar business_unit_id, novos controllers, comissoes/propostas/PDF e evolucoes comerciais da oficial.
- Service Desk: `JrcServiceDesk::Ticket` ja usa `requester_id -> Contact`. `unit -> operator_company` e estrutura OPERADORA, nao a empresa-cliente: nunca mapear operadora/unidade para companies. Adicionar vinculo cliente opcional, separado, tenant-scoped. Preservar SLA versionado, lifecycle, filas, permissoes por unidade, historico append-only, anexos/conversas e idempotencia.
- Projetos: `JrcProjects::Project` tem `contact_id` opcional, tarefas/quadros/marcos/custos/equipe e operation_links. Adicionar company_id opcional sem tornar cliente obrigatorio, manter projetos internos. Origens CRM/chamado/conversa permanecem controladas pelo Access/Linker existente.
- Agenda: `JrcOperations::Agenda` ja agrega tarefas Projetos e atividades/follow-ups CRM. Nao foi encontrado model de tarefa nativa Service Desk; manter `native_tasks_not_available`, sem tratar SLA como tarefa. Adicionar contexto e filtros Empresa/Contato nas fontes reais, sem tabela de agenda nova.
- Customer 360: reaproveitar camada agregadora, acrescentar chamados/projetos e auditorias existentes; todos os scopes/contadores devem reutilizar controles atuais de modulo, unidade, equipe, papel, visibilidade e tenant. Nao expor dados brutos de snapshots nem notas privadas.
- Merge de contatos: a referencia antiga desconhece requester_id de tickets, contact_id de projetos e links de operacoes. Deve ser ampliada para preservar esses vinculos e detectar referencias entre tenants, sem apagar historicos.
- Backfill: referencia anterior insuficiente. Incluir contatos de solicitantes, projetos, origens/links e validacoes de campanhas. Previa revisavel; nomes semelhantes nunca sao correspondencia segura; nenhum UPDATE na fonte sem aplicacao explicita.
- Feature flag `jrc_customer_master` deve ser acrescentada AO FINAL das flags oficiais; nao sobrepor os bits de Service Desk/Flows/Broker/Projetos. Desligada por padrao. Fluxos legados devem continuar com ela desligada.
- Migrations historicas, schema.rb, lockfiles, secrets, Docker/GitHub workflows, SIP/WebRTC, NICO, Flows e os 790 arquivos novos oficiais serao preservados, salvo adicoes pontuais em integracoes documentadas.
- Documentos/evidencias do candidato anterior sao historicos, NAO comprovantes da nova entrega; nao transportar afirmacoes antigas de ausencia de modulos ou testes executados como evidencias novas.

## Conflitos substantivos que exigem preservacao da versao oficial
- `app/controllers/api/v1/accounts/crm/base_controller.rb`
- `app/controllers/api/v1/accounts/crm/deals_controller.rb`
- `app/controllers/api/v1/accounts/crm/leads_controller.rb`
- `app/javascript/dashboard/components-next/sidebar/Sidebar.vue`
- `app/javascript/dashboard/components/widgets/conversation/ConversationSidebar.vue`
- `app/javascript/dashboard/featureFlags.js`
- `app/javascript/dashboard/routes/dashboard/crm/views/deals/DealsIndex.vue`
- `app/javascript/dashboard/routes/dashboard/crm/views/leads/LeadConversionModal.vue`
- `app/javascript/dashboard/routes/dashboard/crm/views/leads/LeadsIndex.vue`
- `app/javascript/dashboard/routes/dashboard/dashboard.routes.js`
- `app/javascript/dashboard/routes/dashboard/webphone/CurrentContactCard.vue`
- `app/javascript/dashboard/routes/dashboard/webphone/WebphonePage.vue`
- `app/models/account.rb`
- `app/models/jrc_crm/audit_event.rb`
- `app/models/jrc_crm/deal.rb`
- `config/features.yml`
- `config/routes.rb`

## Inventario completo
O JSON diferencial anexo lista individualmente exclusivos/modificados, mudancas LF/CRLF, modelos, rotas, frontend, migrations e arquivos de porte.

## Complemento da inspecao comercial antes de integrar Contratos
A oficial contem `JrcCrm::Contract`, SalesOrder, Invoice e BackofficeRequest. Contratos comerciais reais NAO sao a tela planejada de Contratos do Service Desk. Reutilizar vinculos contact/deal/order; incluir contratos autorizados no 360/timeline sem alterar snapshots, termos, assinaturas, documentos ou calculos. O merge de contatos deve preservar tambem as quatro tabelas comerciais.
