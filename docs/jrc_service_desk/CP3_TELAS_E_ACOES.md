# CP3 - Matriz completa de telas e ações

**CP3 IMPLEMENTADO PARA REVISÃO — VALIDAÇÃO NATIVA ACUMULADA PENDENTE**

As ações descritas como frontend estão implementadas no código; sua montagem e execução Vue nativas permanecem pendentes. Não equivalem a persistência nem leitura operacional concluída. Todos os endpoints SD citados são contratos para CP4, não rotas Rails entregues.

## 1. Visão geral

| Campo | Registro |
|---|---|
| ROTA | /app/accounts/:accountId/service-desk |
| NOME | jrc_service_desk_overview |
| REFERÊNCIA | 01 |
| FEATURE FLAG | jrc_service_desk (false; ext_1; 9; 256) |
| COMPONENTES | OverviewView, KpiCard, ServiceDeskPanel, TicketTable, ServiceDeskState |
| FONTE DE DADOS | Agregações não implementadas; GET /tickets preparado para recentes. KPIs/séries indisponíveis. |
| PERMISSÃO | Contexto e tickets.index para recentes; não inferir permissão de KPI. |
| AÇÕES VISÍVEIS | Cards, painéis de gráficos, recentes, atalhos, tarefas, NICO. |
| AÇÕES FUNCIONAIS NA CAMADA FRONTEND | Navegação de atalhos e repetir leitura; sem métricas reais nesta entrega. |
| AÇÕES PENDENTES PARA CP4 | Agregações/KPIs, séries, drill-down, tarefas, NICO e leitura HTTP de recentes. |
| STATUS | ESTRUTURA IMPLEMENTADA; PENDENTE PARA CP4 nas leituras/operacoes; PENDENTE — validação nativa em ambiente Docker/local |

## 2. Chamados

| Campo | Registro |
|---|---|
| ROTA | /app/accounts/:accountId/service-desk/tickets |
| NOME | jrc_service_desk_tickets |
| REFERÊNCIA | 02 |
| FEATURE FLAG | jrc_service_desk (false; ext_1; 9; 256) |
| COMPONENTES | TicketListView, TicketFilters, ScopeBar, LookupSelect, TicketTable, TicketSummary, TabBar, PaginationFooter |
| FONTE DE DADOS | GET /tickets proposto; mine=true na Minha Fila; total/paginação vêm da API, nunca inferidos. |
| PERMISSÃO | tickets.index e permissions.show por registro, Account/unidade autorizadas. |
| AÇÕES VISÍVEIS | Busca, filtros básicos/avançados, ordenação, tabela, prévia, paginação, exportar, abrir formulário. |
| AÇÕES FUNCIONAIS NA CAMADA FRONTEND | Controles de URL, limpar/expandir filtros, navegar, selecionar prévia quando houver payload real. |
| AÇÕES PENDENTES PARA CP4 | Execução das APIs de consulta/prévia, resultados reais de filtros, exportação, assumir próximo e fluxos. |
| STATUS | ESTRUTURA IMPLEMENTADA; PENDENTE PARA CP4 nas leituras/operacoes; PENDENTE — validação nativa em ambiente Docker/local |

## 3. Minha fila

| Campo | Registro |
|---|---|
| ROTA | /app/accounts/:accountId/service-desk/my-queue |
| NOME | jrc_service_desk_mine |
| REFERÊNCIA | 08 |
| FEATURE FLAG | jrc_service_desk (false; ext_1; 9; 256) |
| COMPONENTES | TicketListView, TicketFilters, ScopeBar, LookupSelect, TicketTable, TicketSummary, TabBar, PaginationFooter |
| FONTE DE DADOS | GET /tickets proposto; mine=true na Minha Fila; total/paginação vêm da API, nunca inferidos. |
| PERMISSÃO | tickets.index e permissions.show por registro, Account/unidade autorizadas. |
| AÇÕES VISÍVEIS | Busca, filtros básicos/avançados, ordenação, tabela, prévia, paginação, exportar, abrir formulário. |
| AÇÕES FUNCIONAIS NA CAMADA FRONTEND | Controles de URL, limpar/expandir filtros, navegar, selecionar prévia quando houver payload real. |
| AÇÕES PENDENTES PARA CP4 | Execução das APIs de consulta/prévia, resultados reais de filtros, exportação, assumir próximo e fluxos. |
| STATUS | ESTRUTURA IMPLEMENTADA; PENDENTE PARA CP4 nas leituras/operacoes; PENDENTE — validação nativa em ambiente Docker/local |

## 4. Novo chamado

| Campo | Registro |
|---|---|
| ROTA | /app/accounts/:accountId/service-desk/tickets/new |
| NOME | jrc_service_desk_new |
| REFERÊNCIA | 03-06 |
| FEATURE FLAG | jrc_service_desk (false; ext_1; 9; 256) |
| COMPONENTES | TicketFormView, ScopeBar, LookupSelect, Input, TextArea, PendingAction |
| FONTE DE DADOS | ui_context, lookups por unidade e GET /tickets/:id para edição, todos propostos. |
| PERMISSÃO | unit.permissions.create_ticket na criação; permissions.update no registro carregado na edição. |
| AÇÕES VISÍVEIS | Quatro etapas, dados gerais, classificação, relacionamentos, revisão e resumo lateral. |
| AÇÕES FUNCIONAIS NA CAMADA FRONTEND | Navegar etapas/cancelar; rascunho somente na memória quando houver permissão expressa; nada gravado. |
| AÇÕES PENDENTES PARA CP4 | Criar, salvar, validar regras de negócio, resolver status inicial, idempotência, atribuir, anexar e calcular SLA. |
| STATUS | ESTRUTURA IMPLEMENTADA; PENDENTE PARA CP4 nas leituras/operacoes; PENDENTE — validação nativa em ambiente Docker/local |

## 5. Detalhe do chamado

| Campo | Registro |
|---|---|
| ROTA | /app/accounts/:accountId/service-desk/tickets/:ticketId(\d+) |
| NOME | jrc_service_desk_detail |
| REFERÊNCIA | 07 |
| FEATURE FLAG | jrc_service_desk (false; ext_1; 9; 256) |
| COMPONENTES | TicketDetailView, TicketSummary, TabBar, PendingAction, ServiceDeskState |
| FONTE DE DADOS | GET /tickets/:ticketId proposto; coleções protegidas não carregadas por atalho. |
| PERMISSÃO | Contexto, tickets.index, permissions.show; update/add_note expressos, sem role local. |
| AÇÕES VISÍVEIS | Abas de detalhes/conversas/notas/tarefas/arquivos/SLA/relacionamentos/histórico/solução e ações. |
| AÇÕES FUNCIONAIS NA CAMADA FRONTEND | Trocar abas, voltar, navegar para edição se autorizada; nota local sem envio quando permitida. |
| AÇÕES PENDENTES PARA CP4 | Ler detalhes reais via API, atribuir, transferir, pausar, resolver/reabrir, notas, anexos, conversas e histórico. |
| STATUS | ESTRUTURA IMPLEMENTADA; PENDENTE PARA CP4 nas leituras/operacoes; PENDENTE — validação nativa em ambiente Docker/local |

## 6. Editar chamado

| Campo | Registro |
|---|---|
| ROTA | /app/accounts/:accountId/service-desk/tickets/:ticketId(\d+)/edit |
| NOME | jrc_service_desk_edit |
| REFERÊNCIA | 07 (adaptação) |
| FEATURE FLAG | jrc_service_desk (false; ext_1; 9; 256) |
| COMPONENTES | TicketFormView, ScopeBar, LookupSelect, Input, TextArea, PendingAction |
| FONTE DE DADOS | ui_context, lookups por unidade e GET /tickets/:id para edição, todos propostos. |
| PERMISSÃO | unit.permissions.create_ticket na criação; permissions.update no registro carregado na edição. |
| AÇÕES VISÍVEIS | Quatro etapas, dados gerais, classificação, relacionamentos, revisão e resumo lateral. |
| AÇÕES FUNCIONAIS NA CAMADA FRONTEND | Navegar etapas/cancelar; rascunho somente na memória quando houver permissão expressa; nada gravado. |
| AÇÕES PENDENTES PARA CP4 | Criar, salvar, validar regras de negócio, resolver status inicial, idempotência, atribuir, anexar e calcular SLA. |
| STATUS | ESTRUTURA IMPLEMENTADA; PENDENTE PARA CP4 nas leituras/operacoes; PENDENTE — validação nativa em ambiente Docker/local |

## 7. Filas e equipes

| Campo | Registro |
|---|---|
| ROTA | /app/accounts/:accountId/service-desk/queues |
| NOME | jrc_service_desk_queues |
| REFERÊNCIA | 09 |
| FEATURE FLAG | jrc_service_desk (false; ext_1; 9; 256) |
| COMPONENTES | CatalogView, ScopeBar, BaseTable/Row/Cell, Input, PaginationFooter, PendingAction |
| FONTE DE DADOS | GET /queues proposto, ui_context e paginação do servidor. |
| PERMISSÃO | queues.index e permissions.show; sem autoconcessão ou bypass de administrador. |
| AÇÕES VISÍVEIS | Busca, escopo, colunas, paginação, prévia, estrutura de campos e ações desabilitadas. |
| AÇÕES FUNCIONAIS NA CAMADA FRONTEND | Alternar prévia/campos, atualizar filtros na URL e consultar estrutura; dados dependem da API. |
| AÇÕES PENDENTES PARA CP4 | Leitura real e criar/editar/ativar/desativar/excluir; provisionamento de unidades/vínculos e regras de filas. |
| STATUS | ESTRUTURA IMPLEMENTADA; PENDENTE PARA CP4 nas leituras/operacoes; PENDENTE — validação nativa em ambiente Docker/local |

## 8. Responsáveis

| Campo | Registro |
|---|---|
| ROTA | /app/accounts/:accountId/service-desk/assignees |
| NOME | jrc_service_desk_assignees |
| REFERÊNCIA | 09 |
| FEATURE FLAG | jrc_service_desk (false; ext_1; 9; 256) |
| COMPONENTES | CatalogView, ScopeBar, BaseTable/Row/Cell, Input, PaginationFooter, PendingAction |
| FONTE DE DADOS | GET /assignees proposto, ui_context e paginação do servidor. |
| PERMISSÃO | assignees.index e permissions.show; sem autoconcessão ou bypass de administrador. |
| AÇÕES VISÍVEIS | Busca, escopo, colunas, paginação, prévia, estrutura de campos e ações desabilitadas. |
| AÇÕES FUNCIONAIS NA CAMADA FRONTEND | Alternar prévia/campos, atualizar filtros na URL e consultar estrutura; dados dependem da API. |
| AÇÕES PENDENTES PARA CP4 | Leitura real e criar/editar/ativar/desativar/excluir; provisionamento de unidades/vínculos e regras de filas. |
| STATUS | ESTRUTURA IMPLEMENTADA; PENDENTE PARA CP4 nas leituras/operacoes; PENDENTE — validação nativa em ambiente Docker/local |

## 9. SLA

| Campo | Registro |
|---|---|
| ROTA | /app/accounts/:accountId/service-desk/sla |
| NOME | jrc_service_desk_sla |
| REFERÊNCIA | 10 |
| FEATURE FLAG | jrc_service_desk (false; ext_1; 9; 256) |
| COMPONENTES | PlannedView, TabBar, ServiceDeskPanel, ServiceDeskState, Input, PendingAction |
| FONTE DE DADOS | Sem endpoint conectado. Esquema visual referencial, sem registros, séries ou resultados inventados. |
| PERMISSÃO | sla.index deve vir da API para navegar com contexto confirmado; ações permanecem indisponíveis. |
| AÇÕES VISÍVEIS | Lista/colunas, abas, filtros desabilitados, painéis e ações da referência. |
| AÇÕES FUNCIONAIS NA CAMADA FRONTEND | Alternar abas da estrutura, sem consulta ou efeito de negócio. |
| AÇÕES PENDENTES PARA CP4 | Backend/contratos de leitura e ações correspondentes, autorizações e dados. Não confundir com domínio CP2 já completo. |
| STATUS | ESTRUTURA IMPLEMENTADA; PENDENTE PARA CP4 nas leituras/operacoes; PENDENTE — validação nativa em ambiente Docker/local |

## 10. Catálogo de serviços

| Campo | Registro |
|---|---|
| ROTA | /app/accounts/:accountId/service-desk/catalog |
| NOME | jrc_service_desk_catalog |
| REFERÊNCIA | 11 |
| FEATURE FLAG | jrc_service_desk (false; ext_1; 9; 256) |
| COMPONENTES | PlannedView, TabBar, ServiceDeskPanel, ServiceDeskState, Input, PendingAction |
| FONTE DE DADOS | Sem endpoint conectado. Esquema visual referencial, sem registros, séries ou resultados inventados. |
| PERMISSÃO | catalog.index deve vir da API para navegar com contexto confirmado; ações permanecem indisponíveis. |
| AÇÕES VISÍVEIS | Lista/colunas, abas, filtros desabilitados, painéis e ações da referência. |
| AÇÕES FUNCIONAIS NA CAMADA FRONTEND | Alternar abas da estrutura, sem consulta ou efeito de negócio. |
| AÇÕES PENDENTES PARA CP4 | Backend/contratos de leitura e ações correspondentes, autorizações e dados. Não confundir com domínio CP2 já completo. |
| STATUS | ESTRUTURA IMPLEMENTADA; PENDENTE PARA CP4 nas leituras/operacoes; PENDENTE — validação nativa em ambiente Docker/local |

## 11. Base de conhecimento

| Campo | Registro |
|---|---|
| ROTA | /app/accounts/:accountId/service-desk/knowledge |
| NOME | jrc_service_desk_knowledge |
| REFERÊNCIA | 12 |
| FEATURE FLAG | jrc_service_desk (false; ext_1; 9; 256) |
| COMPONENTES | PlannedView, TabBar, ServiceDeskPanel, ServiceDeskState, Input, PendingAction |
| FONTE DE DADOS | Sem endpoint conectado. Esquema visual referencial, sem registros, séries ou resultados inventados. |
| PERMISSÃO | knowledge.index deve vir da API para navegar com contexto confirmado; ações permanecem indisponíveis. |
| AÇÕES VISÍVEIS | Lista/colunas, abas, filtros desabilitados, painéis e ações da referência. |
| AÇÕES FUNCIONAIS NA CAMADA FRONTEND | Alternar abas da estrutura, sem consulta ou efeito de negócio. |
| AÇÕES PENDENTES PARA CP4 | Backend/contratos de leitura e ações correspondentes, autorizações e dados. Não confundir com domínio CP2 já completo. |
| STATUS | ESTRUTURA IMPLEMENTADA; PENDENTE PARA CP4 nas leituras/operacoes; PENDENTE — validação nativa em ambiente Docker/local |

## 12. Aprovações

| Campo | Registro |
|---|---|
| ROTA | /app/accounts/:accountId/service-desk/approvals |
| NOME | jrc_service_desk_approvals |
| REFERÊNCIA | 13 |
| FEATURE FLAG | jrc_service_desk (false; ext_1; 9; 256) |
| COMPONENTES | PlannedView, TabBar, ServiceDeskPanel, ServiceDeskState, Input, PendingAction |
| FONTE DE DADOS | Sem endpoint conectado. Esquema visual referencial, sem registros, séries ou resultados inventados. |
| PERMISSÃO | approvals.index deve vir da API para navegar com contexto confirmado; ações permanecem indisponíveis. |
| AÇÕES VISÍVEIS | Lista/colunas, abas, filtros desabilitados, painéis e ações da referência. |
| AÇÕES FUNCIONAIS NA CAMADA FRONTEND | Alternar abas da estrutura, sem consulta ou efeito de negócio. |
| AÇÕES PENDENTES PARA CP4 | Backend/contratos de leitura e ações correspondentes, autorizações e dados. Não confundir com domínio CP2 já completo. |
| STATUS | ESTRUTURA IMPLEMENTADA; PENDENTE PARA CP4 nas leituras/operacoes; PENDENTE — validação nativa em ambiente Docker/local |

## 13. Problemas

| Campo | Registro |
|---|---|
| ROTA | /app/accounts/:accountId/service-desk/problems |
| NOME | jrc_service_desk_problems |
| REFERÊNCIA | 14 |
| FEATURE FLAG | jrc_service_desk (false; ext_1; 9; 256) |
| COMPONENTES | PlannedView, TabBar, ServiceDeskPanel, ServiceDeskState, Input, PendingAction |
| FONTE DE DADOS | Sem endpoint conectado. Esquema visual referencial, sem registros, séries ou resultados inventados. |
| PERMISSÃO | problems.index deve vir da API para navegar com contexto confirmado; ações permanecem indisponíveis. |
| AÇÕES VISÍVEIS | Lista/colunas, abas, filtros desabilitados, painéis e ações da referência. |
| AÇÕES FUNCIONAIS NA CAMADA FRONTEND | Alternar abas da estrutura, sem consulta ou efeito de negócio. |
| AÇÕES PENDENTES PARA CP4 | Backend/contratos de leitura e ações correspondentes, autorizações e dados. Não confundir com domínio CP2 já completo. |
| STATUS | ESTRUTURA IMPLEMENTADA; PENDENTE PARA CP4 nas leituras/operacoes; PENDENTE — validação nativa em ambiente Docker/local |

## 14. Mudanças

| Campo | Registro |
|---|---|
| ROTA | /app/accounts/:accountId/service-desk/changes |
| NOME | jrc_service_desk_changes |
| REFERÊNCIA | 15 |
| FEATURE FLAG | jrc_service_desk (false; ext_1; 9; 256) |
| COMPONENTES | PlannedView, TabBar, ServiceDeskPanel, ServiceDeskState, Input, PendingAction |
| FONTE DE DADOS | Sem endpoint conectado. Esquema visual referencial, sem registros, séries ou resultados inventados. |
| PERMISSÃO | changes.index deve vir da API para navegar com contexto confirmado; ações permanecem indisponíveis. |
| AÇÕES VISÍVEIS | Lista/colunas, abas, filtros desabilitados, painéis e ações da referência. |
| AÇÕES FUNCIONAIS NA CAMADA FRONTEND | Alternar abas da estrutura, sem consulta ou efeito de negócio. |
| AÇÕES PENDENTES PARA CP4 | Backend/contratos de leitura e ações correspondentes, autorizações e dados. Não confundir com domínio CP2 já completo. |
| STATUS | ESTRUTURA IMPLEMENTADA; PENDENTE PARA CP4 nas leituras/operacoes; PENDENTE — validação nativa em ambiente Docker/local |

## 15. Ativos e equipamentos

| Campo | Registro |
|---|---|
| ROTA | /app/accounts/:accountId/service-desk/assets |
| NOME | jrc_service_desk_assets |
| REFERÊNCIA | 16 |
| FEATURE FLAG | jrc_service_desk (false; ext_1; 9; 256) |
| COMPONENTES | PlannedView, TabBar, ServiceDeskPanel, ServiceDeskState, Input, PendingAction |
| FONTE DE DADOS | Sem endpoint conectado. Esquema visual referencial, sem registros, séries ou resultados inventados. |
| PERMISSÃO | assets.index deve vir da API para navegar com contexto confirmado; ações permanecem indisponíveis. |
| AÇÕES VISÍVEIS | Lista/colunas, abas, filtros desabilitados, painéis e ações da referência. |
| AÇÕES FUNCIONAIS NA CAMADA FRONTEND | Alternar abas da estrutura, sem consulta ou efeito de negócio. |
| AÇÕES PENDENTES PARA CP4 | Backend/contratos de leitura e ações correspondentes, autorizações e dados. Não confundir com domínio CP2 já completo. |
| STATUS | ESTRUTURA IMPLEMENTADA; PENDENTE PARA CP4 nas leituras/operacoes; PENDENTE — validação nativa em ambiente Docker/local |

## 16. Condições contratuais

| Campo | Registro |
|---|---|
| ROTA | /app/accounts/:accountId/service-desk/contracts |
| NOME | jrc_service_desk_contracts |
| REFERÊNCIA | 17 |
| FEATURE FLAG | jrc_service_desk (false; ext_1; 9; 256) |
| COMPONENTES | PlannedView, TabBar, ServiceDeskPanel, ServiceDeskState, Input, PendingAction |
| FONTE DE DADOS | Sem endpoint conectado. Esquema visual referencial, sem registros, séries ou resultados inventados. |
| PERMISSÃO | contracts.index deve vir da API para navegar com contexto confirmado; ações permanecem indisponíveis. |
| AÇÕES VISÍVEIS | Lista/colunas, abas, filtros desabilitados, painéis e ações da referência. |
| AÇÕES FUNCIONAIS NA CAMADA FRONTEND | Alternar abas da estrutura, sem consulta ou efeito de negócio. |
| AÇÕES PENDENTES PARA CP4 | Backend/contratos de leitura e ações correspondentes, autorizações e dados. Não confundir com domínio CP2 já completo. |
| STATUS | ESTRUTURA IMPLEMENTADA; PENDENTE PARA CP4 nas leituras/operacoes; PENDENTE — validação nativa em ambiente Docker/local |

## 17. Automações

| Campo | Registro |
|---|---|
| ROTA | /app/accounts/:accountId/service-desk/automations |
| NOME | jrc_service_desk_automations |
| REFERÊNCIA | 18 |
| FEATURE FLAG | jrc_service_desk (false; ext_1; 9; 256) |
| COMPONENTES | PlannedView, TabBar, ServiceDeskPanel, ServiceDeskState, Input, PendingAction |
| FONTE DE DADOS | Sem endpoint conectado. Esquema visual referencial, sem registros, séries ou resultados inventados. |
| PERMISSÃO | automations.index deve vir da API para navegar com contexto confirmado; ações permanecem indisponíveis. |
| AÇÕES VISÍVEIS | Lista/colunas, abas, filtros desabilitados, painéis e ações da referência. |
| AÇÕES FUNCIONAIS NA CAMADA FRONTEND | Alternar abas da estrutura, sem consulta ou efeito de negócio. |
| AÇÕES PENDENTES PARA CP4 | Backend/contratos de leitura e ações correspondentes, autorizações e dados. Não confundir com domínio CP2 já completo. |
| STATUS | ESTRUTURA IMPLEMENTADA; PENDENTE PARA CP4 nas leituras/operacoes; PENDENTE — validação nativa em ambiente Docker/local |

## 18. Pesquisas de satisfação

| Campo | Registro |
|---|---|
| ROTA | /app/accounts/:accountId/service-desk/surveys |
| NOME | jrc_service_desk_surveys |
| REFERÊNCIA | 19 |
| FEATURE FLAG | jrc_service_desk (false; ext_1; 9; 256) |
| COMPONENTES | PlannedView, TabBar, ServiceDeskPanel, ServiceDeskState, Input, PendingAction |
| FONTE DE DADOS | Sem endpoint conectado. Esquema visual referencial, sem registros, séries ou resultados inventados. |
| PERMISSÃO | surveys.index deve vir da API para navegar com contexto confirmado; ações permanecem indisponíveis. |
| AÇÕES VISÍVEIS | Lista/colunas, abas, filtros desabilitados, painéis e ações da referência. |
| AÇÕES FUNCIONAIS NA CAMADA FRONTEND | Alternar abas da estrutura, sem consulta ou efeito de negócio. |
| AÇÕES PENDENTES PARA CP4 | Backend/contratos de leitura e ações correspondentes, autorizações e dados. Não confundir com domínio CP2 já completo. |
| STATUS | ESTRUTURA IMPLEMENTADA; PENDENTE PARA CP4 nas leituras/operacoes; PENDENTE — validação nativa em ambiente Docker/local |

## 19. Relatórios

| Campo | Registro |
|---|---|
| ROTA | /app/accounts/:accountId/service-desk/reports |
| NOME | jrc_service_desk_reports |
| REFERÊNCIA | 20 |
| FEATURE FLAG | jrc_service_desk (false; ext_1; 9; 256) |
| COMPONENTES | PlannedView, TabBar, ServiceDeskPanel, ServiceDeskState, Input, PendingAction |
| FONTE DE DADOS | Sem endpoint conectado. Esquema visual referencial, sem registros, séries ou resultados inventados. |
| PERMISSÃO | reports.index deve vir da API para navegar com contexto confirmado; ações permanecem indisponíveis. |
| AÇÕES VISÍVEIS | Lista/colunas, abas, filtros desabilitados, painéis e ações da referência. |
| AÇÕES FUNCIONAIS NA CAMADA FRONTEND | Alternar abas da estrutura, sem consulta ou efeito de negócio. |
| AÇÕES PENDENTES PARA CP4 | Backend/contratos de leitura e ações correspondentes, autorizações e dados. Não confundir com domínio CP2 já completo. |
| STATUS | ESTRUTURA IMPLEMENTADA; PENDENTE PARA CP4 nas leituras/operacoes; PENDENTE — validação nativa em ambiente Docker/local |

## 20. Configurações

| Campo | Registro |
|---|---|
| ROTA | /app/accounts/:accountId/service-desk/settings |
| NOME | jrc_service_desk_settings |
| REFERÊNCIA | 21 |
| FEATURE FLAG | jrc_service_desk (false; ext_1; 9; 256) |
| COMPONENTES | SettingsView, ServiceDeskPanel, Button, PendingAction |
| FONTE DE DADOS | Metadados de navegação e capacidades do ui_context proposto; nenhum cadastro mestre criado. |
| PERMISSÃO | settings.index e capacidades de cada destino; nenhuma dedução de role. |
| AÇÕES VISÍVEIS | Cards de configuração e aviso de identidade separada do portal. |
| AÇÕES FUNCIONAIS NA CAMADA FRONTEND | Navegar para os esquemas de cada cadastro. |
| AÇÕES PENDENTES PARA CP4 | Persistência e concessões administrativas; portal e impersonação não implementados. |
| STATUS | ESTRUTURA IMPLEMENTADA; PENDENTE PARA CP4 nas leituras/operacoes; PENDENTE — validação nativa em ambiente Docker/local |

## 21. Prioridades

| Campo | Registro |
|---|---|
| ROTA | /app/accounts/:accountId/service-desk/settings/priorities |
| NOME | jrc_service_desk_priorities |
| REFERÊNCIA | 21 |
| FEATURE FLAG | jrc_service_desk (false; ext_1; 9; 256) |
| COMPONENTES | CatalogView, ScopeBar, BaseTable/Row/Cell, Input, PaginationFooter, PendingAction |
| FONTE DE DADOS | GET /priorities proposto, ui_context e paginação do servidor. |
| PERMISSÃO | priorities.index e permissions.show; sem autoconcessão ou bypass de administrador. |
| AÇÕES VISÍVEIS | Busca, escopo, colunas, paginação, prévia, estrutura de campos e ações desabilitadas. |
| AÇÕES FUNCIONAIS NA CAMADA FRONTEND | Alternar prévia/campos, atualizar filtros na URL e consultar estrutura; dados dependem da API. |
| AÇÕES PENDENTES PARA CP4 | Leitura real e criar/editar/ativar/desativar/excluir; provisionamento de unidades/vínculos e regras de filas. |
| STATUS | ESTRUTURA IMPLEMENTADA; PENDENTE PARA CP4 nas leituras/operacoes; PENDENTE — validação nativa em ambiente Docker/local |

## 22. Categorias

| Campo | Registro |
|---|---|
| ROTA | /app/accounts/:accountId/service-desk/settings/categories |
| NOME | jrc_service_desk_categories |
| REFERÊNCIA | 21 |
| FEATURE FLAG | jrc_service_desk (false; ext_1; 9; 256) |
| COMPONENTES | CatalogView, ScopeBar, BaseTable/Row/Cell, Input, PaginationFooter, PendingAction |
| FONTE DE DADOS | GET /categories proposto, ui_context e paginação do servidor. |
| PERMISSÃO | categories.index e permissions.show; sem autoconcessão ou bypass de administrador. |
| AÇÕES VISÍVEIS | Busca, escopo, colunas, paginação, prévia, estrutura de campos e ações desabilitadas. |
| AÇÕES FUNCIONAIS NA CAMADA FRONTEND | Alternar prévia/campos, atualizar filtros na URL e consultar estrutura; dados dependem da API. |
| AÇÕES PENDENTES PARA CP4 | Leitura real e criar/editar/ativar/desativar/excluir; provisionamento de unidades/vínculos e regras de filas. |
| STATUS | ESTRUTURA IMPLEMENTADA; PENDENTE PARA CP4 nas leituras/operacoes; PENDENTE — validação nativa em ambiente Docker/local |

## 23. Status

| Campo | Registro |
|---|---|
| ROTA | /app/accounts/:accountId/service-desk/settings/statuses |
| NOME | jrc_service_desk_statuses |
| REFERÊNCIA | 21 |
| FEATURE FLAG | jrc_service_desk (false; ext_1; 9; 256) |
| COMPONENTES | CatalogView, ScopeBar, BaseTable/Row/Cell, Input, PaginationFooter, PendingAction |
| FONTE DE DADOS | GET /statuses proposto, ui_context e paginação do servidor. |
| PERMISSÃO | statuses.index e permissions.show; sem autoconcessão ou bypass de administrador. |
| AÇÕES VISÍVEIS | Busca, escopo, colunas, paginação, prévia, estrutura de campos e ações desabilitadas. |
| AÇÕES FUNCIONAIS NA CAMADA FRONTEND | Alternar prévia/campos, atualizar filtros na URL e consultar estrutura; dados dependem da API. |
| AÇÕES PENDENTES PARA CP4 | Leitura real e criar/editar/ativar/desativar/excluir; provisionamento de unidades/vínculos e regras de filas. |
| STATUS | ESTRUTURA IMPLEMENTADA; PENDENTE PARA CP4 nas leituras/operacoes; PENDENTE — validação nativa em ambiente Docker/local |

## 24. Unidades

| Campo | Registro |
|---|---|
| ROTA | /app/accounts/:accountId/service-desk/settings/units |
| NOME | jrc_service_desk_units |
| REFERÊNCIA | 21 + CP2-D01 |
| FEATURE FLAG | jrc_service_desk (false; ext_1; 9; 256) |
| COMPONENTES | CatalogView, ScopeBar, BaseTable/Row/Cell, Input, PaginationFooter, PendingAction |
| FONTE DE DADOS | GET /units proposto, ui_context e paginação do servidor. |
| PERMISSÃO | units.index e permissions.show; sem autoconcessão ou bypass de administrador. |
| AÇÕES VISÍVEIS | Busca, escopo, colunas, paginação, prévia, estrutura de campos e ações desabilitadas. |
| AÇÕES FUNCIONAIS NA CAMADA FRONTEND | Alternar prévia/campos, atualizar filtros na URL e consultar estrutura; dados dependem da API. |
| AÇÕES PENDENTES PARA CP4 | Leitura real e criar/editar/ativar/desativar/excluir; provisionamento de unidades/vínculos e regras de filas. |
| STATUS | ESTRUTURA IMPLEMENTADA; PENDENTE PARA CP4 nas leituras/operacoes; PENDENTE — validação nativa em ambiente Docker/local |

## 25. Empresas operadoras

| Campo | Registro |
|---|---|
| ROTA | /app/accounts/:accountId/service-desk/settings/operator-companies |
| NOME | jrc_service_desk_operator_companies |
| REFERÊNCIA | 21 + CP2-D01 |
| FEATURE FLAG | jrc_service_desk (false; ext_1; 9; 256) |
| COMPONENTES | CatalogView, ScopeBar, BaseTable/Row/Cell, Input, PaginationFooter, PendingAction |
| FONTE DE DADOS | GET /operator_companies proposto, ui_context e paginação do servidor. |
| PERMISSÃO | operator_companies.index e permissions.show; sem autoconcessão ou bypass de administrador. |
| AÇÕES VISÍVEIS | Busca, escopo, colunas, paginação, prévia, estrutura de campos e ações desabilitadas. |
| AÇÕES FUNCIONAIS NA CAMADA FRONTEND | Alternar prévia/campos, atualizar filtros na URL e consultar estrutura; dados dependem da API. |
| AÇÕES PENDENTES PARA CP4 | Leitura real e criar/editar/ativar/desativar/excluir; provisionamento de unidades/vínculos e regras de filas. |
| STATUS | ESTRUTURA IMPLEMENTADA; PENDENTE PARA CP4 nas leituras/operacoes; PENDENTE — validação nativa em ambiente Docker/local |

## Exclusões explícitas

Portal externo (referência 22): nenhuma rota/tela/sessão de cliente; somente aviso de fronteira em Configurações. Projetos: nenhuma rota, menu ou implementação. KPIs: nenhum total de demonstração ou série sintética. Nenhum POST/PATCH/DELETE do Service Desk.

**CP4 NÃO INICIADO.**
