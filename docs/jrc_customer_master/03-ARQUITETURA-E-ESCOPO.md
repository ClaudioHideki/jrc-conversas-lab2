# Arquitetura e escopo do Cadastro Mestre

## Fonte e estrategia

A fonte oficial e o ZIP 80f7305, SHA-256 `69717c07f0143304ee2ec7e8983851d6caf58b0963d630b199b97f9c4819c5f4`.
A referencia anterior tem SHA-256 `9bb22e9a16ac9c122d0697cde207baf8389d541559a4b6c4ce34dad7ea8734c9`.
Foi usada uma ancestral somente para identificar quais mudancas pertenciam ao Cadastro Mestre, nunca para reconstituir a base atual.
790 arquivos exclusivos da oficial foram preservados. Entre os 35 arquivos modificados pela referencia, 17 tinham evolucoes substantivas na oficial.
Os finais de linha CRLF da oficial foram preservados nos arquivos existentes; nao houve normalizacao global.
`LeadsIndex.vue` permaneceu identico a oficial: o seletor foi portado para o novo `LeadCreateModal.vue`, conservando a criacao/deduplicacao atual.
Navegacao de Service Desk, Projetos, Minha Agenda, Flows e acoes OperationsLinks na conversa foram mantidas.

## Entidades centrais

`JrcCustomers::Company` e um adapter Rails para a tabela EXISTENTE `companies`. Nao e outra tabela de empresas.
`Company` Enterprise continua existindo e acessando os mesmos IDs. `Contact` e `ContactInbox` continuam as entidades nativas.
Empresa possui PF/PJ, CPF/CNPJ normalizado, razao/nome, fantasia, inscricoes, segmento, porte, site, origem, responsavel, grupo, matriz/filiais, relacionamento e ativo.
Relacionamentos: prospect, lead, customer, former_customer, partner, supplier, internal e other. Cadastro tecnico de Contact permanece provisional e nao significa Cliente.
`company_addresses` e `contact_points` guardam enderecos e meios adicionais; nao substituem ContactInbox/source_id de provedores.
Segmentos e grupos usam atributos empresariais e filtros existentes, sem criar um cadastro empresarial equivalente por modulo.

## Service Desk

`Ticket.requester_id` ja aponta para Contact e foi preservado. Foi adicionado `Ticket.company_id`, nullable, para a empresa ATENDIDA.
`Ticket.unit_id -> Unit.operator_company_id` permanece a estrutura OPERADORA. Nunca e utilizado como identificador da empresa atendida.
Criacao e edicao nativas aceitam a empresa quando a feature e a autorizacao permitem. O solicitante infere a empresa quando nao houver escolha explicita.
Escolhas conflitantes com solicitante ou projeto vinculado sao recusadas, nao conciliadas silenciosamente. Limpar um vinculo exigido pela origem e recusado.
Parametros originais, idempotencia, lock_version, status/prioridade, SLA/ciclos/versoes, historico, filas, equipes, anexos/notas e permissoes por unidade permanecem nativos.
Quando company_id nao vem na criacao, o fingerprint antigo e preservado para permitir replay de solicitacoes feitas antes da ativacao.
O formulario, presenter e confirmacao de escrita incluem a nova empresa sem criar um fluxo paralelo de chamados.

## Projetos

`Project.company_id` e opcional; projetos internos continuam sem contato/empresa obrigatorios.
A criacao infere a empresa pelo contato ou origem autorizada (Deal, Ticket, Conversation). O Linker existente continua controlando os vinculos.
Quadros, tarefas, dependencias, checklist, comentarios, horas, anexos, equipe, custos, marcos, cronograma, modelos, prioridade, aceite e ownership nao foram recriados.
Troca explicita de empresa passa por account, permissoes e revisao de conflitos. Uma simples alteracao de titulo nao reatribui a empresa historica caso o contato tenha mudado de empresa depois.

## CRM e comercial

Organization legado recebe mapeamento para companies; seus IDs e JSON continuam existindo. Nomes semelhantes nao sao prova suficiente para mesclar.
LeadCreateModal e LeadCreationService atuais foram preservados, incluindo a resolucao nativa de Contact e a reutilizacao de Lead existente.
Identificadores adicionais complementam a busca de Contact sem sobrepor source_id/inbox. Reutilizar um Lead existente com outra empresa exige revisao explicita.
Leads, Deals, Activities e conversao consomem o mestre; Proposal continua vinculada ao Deal existente.
SalesOrder, Contract, Invoice e BackofficeRequest ja apontam para Contact e/ou Deal. Seus snapshots, calculos, PDFs, assinaturas e termos comerciais nao foram reescritos.
Contratos comerciais e pedidos reais sao fontes do 360. Nao foram confundidos com a tela de Contratos planejada no Service Desk.

## Customer360 e timeline

Empresas possuem abas de dados, enderecos, contatos, conversas, CRM, chamados, projetos/tarefas, atividades/follow-ups, contratos/pedidos, chamadas e campanhas quando a origem e autorizada.
Contadores vem de queries reais; fontes sem acesso/estrutura nao sao representadas por zeros artificiais.
Conversas usam `Conversations::PermissionFilterService` nativo. Chamadas respeitam conversas acessiveis e, para agentes comuns, `accepted_by_agent_id`, como no CallFinder.
CRM exige a feature e permissao `jrc_crm`, alem dos escopos de responsavel. Projetos usam Access/Authorization; Service Desk usa contexto, policy, unidade e permissoes de clientes/historico.
Timeline agrega Message publico, auditoria CRM, atividades, chamadas/envios, TicketEvent e AuditEvent de Projetos. Nao foi criada uma tabela geral de eventos.
Nao retorna conteudo de mensagens privadas, notas internas, snapshots financeiros, tokens, configuracoes ou JSON bruto de auditoria.
Cursores sao assinados e vinculados a Account, usuario e recurso. Listas e totais reaplicam autorizacao.

## Minha Agenda

`/minha-agenda`, `AgendaPage.vue` e `JrcOperations::Agenda` foram preservados.
A fonte continua Projetos Tasks + CRM Activities/FollowUps. Ha enriquecimento por Empresa/Contato e filtros company_id/contact_id, usando as mesmas fontes autorizadas do 360.
Regras de timezone, datas sem horario, limite por fonte, responsaveis, views e edicao na origem foram mantidas.
Nao existe Task nativa Service Desk adequada nesta fonte. `native_tasks_not_available` permanece no backend e visivel na tela. SLA nao virou tarefa.

## Merge e backfill

O merge continua `ContactMergeAction`, ampliado transacionalmente para preservar os novos vinculos: requester dos chamados, Contact de Projetos, pedidos/contratos/faturas/backoffice, CRM, campanhas, Calls, NICO, labels e avatares.
Nao altera fingerprints historicos, SLA, snapshots, configuracao SIP ou identificadores de provedores. Conflitos de empresa/identificador externo/ERP e referencias de outro tenant bloqueiam a mescla.
Antes de destruir o Contact de origem, verifica que referencias nativas realmente foram movidas. Uma falha de update provoca rollback em vez de apagar a origem.
Backfill CRM e operacional possuem dry run e aplicacao explicita por digest revisado, com auditoria. A aplicacao revisada e transacional; a rotina deve rodar em manutencao, pois nem todos os consumidores antigos usam lock de Account.
Pode ser necessaria nova rodada de dry run depois de aplicar um estagio, pois as referencias resolvidas passam a servir de evidencia para o proximo. Nao e inferida empresa por nome/telefone compartilhado ou por operadora.

## Limites deliberados

A estrutura de consulta CNPJ continua opcional e sem fornecedor externo executado. NICO foi preservado, sem novas ferramentas autonomas de Customer360.
O lookup de telefone/ramal foi complementado, mas nao criou CDR SIP central nem alterou telefonia/protocolos. O historico SIP local nao e apresentado como CDR central.
A importacao de Empresas e propria do mestre, com previa; o CSV legado CRM possui inconsistencias preexistentes e nao foi certificado.
O fluxo nativo de criacao de Lead permanece no CRM/contato/conversa; nao foi criado um novo painel universal de quatro acoes para todos os canais.
Telas Service Desk marcadas planned continuam assim. Esta entrega nao declara concluidas funcionalidades planejadas da base.
