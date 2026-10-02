# API e vinculos reais

Prefixo novo: `/api/v1/accounts/:account_id/customers`. Todas as rotas exigem a feature e DirectoryPolicy; a Account vem da sessao/contexto autorizado.

## Diretorio

GET metadata e identity; companies GET/index/show e POST/PATCH; GET companies/duplicates por identificador fiscal normalizado; GET companies/:id/overview, /timeline e /records?kind=...
Contatos: GET/index/show, POST/PATCH, GET duplicates/timeline e POST merge. Merge exige administrador e confirm=true.
Enderecos: POST/PATCH/DELETE em companies/:company_id/addresses; meios: POST/PATCH/DELETE em contacts/:contact_id/contact_points.
Importacao: POST imports/preview e imports/apply, com arquivo e token de previa vinculado a conteudo/Account. Somente administracao.
Atualizacao de Empresa exige revision da leitura anterior. Reatribuicao de Contact ja vinculado exige confirmacao explicita.

## Consumers preservados

Service Desk usa as mesmas rotas e servicos nativos. `ticket.company_id` opcional somente quando habilitado; `requester_id` continua Contact e `unit_id` continua unidade operadora.
A edicao exige a mesma versao esperada e politica de acesso a cliente; a confirmacao de escrita compara company_id ao dado persistido.
Projetos usam as mesmas rotas sob `projects/projects`, com project.company_id opcional quando habilitado. Owner/visibility/Contact/origem/lock_version continuam com as validacoes existentes.
CRM Leads/Deals/conversao usam company_id sem duplicar a empresa. Contratos/pedidos continuam referenciando Contact/Deal/Order nativos.
Agenda GET operations/agenda aceita company_id/contact_id junto aos filtros existentes; o resultado pode incluir company/contact minimos por item, autorizado por diretoria e fonte.
Company360 records suporta conversas, leads, deals, propostas, atividades, tickets, projects, project_tasks, contracts, orders, follow_ups, calls e campaigns conforme estrutura/permissoes.

## Dados e seguranca

IDs internos nao sao CPF/CNPJ/e-mail/telefone. Todas as resolucoes empresariais se restringem a account_id.
Empresa atendida nao e operator_company_id, organization_id antigo, business_unit_id comercial ou ID ERP do NICO.
Nao sao expostos snapshots privados, credenciais, transcricoes ou configuracoes em records/timeline. Cursores expiram e sao restritos a usuario/conta/recurso.
Filtros de Campanhas operam sobre Contact/AudienceResolver atuais, sem mudar consentimento, blacklist, recipients ou envio.
Na Telefonia ha consulta de identidade suplementar; nao houve mudanca de protocolo, configuracao de registro nem criacao de CDR central.
