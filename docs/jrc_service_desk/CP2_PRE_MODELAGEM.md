# Estado atual - CP2 apos aprovacao humana

CP2-D01/CP2-D02: APROVADAS, opcao A. Fundacao implementada para revisao.
Consulte `CP2_IMPLEMENTACAO.md` para o resultado atual e `CP2_MODELO_DE_DADOS.md` para as
fichas executaveis. Specs escritos nao equivalem a execucao nativa.
**PENDENTE — validação nativa em ambiente Docker/local**.
Nenhum CP3 iniciado. Nenhuma CP2-D03+ pendente nesta rodada.

## Historico preservado da preparacao (nao e o estado atual da implementacao)

> Atualizacao de continuidade: CP2-D01 e CP2-D02 foram APROVADAS, opcao A.
> O conteudo abaixo preserva a preparacao anterior. O desenho executavel, resultados e
> testes atuais sao registrados em CP2_MODELO_DE_DADOS.md e CP2_IMPLEMENTACAO.md.
> SD-D01 a SD-D05 permanecem obrigatorias. Somente CP2 autorizado.

# CP2 - pre-modelagem condicionada, sem DDL

**Status: proposta documental BLOQUEADA por CP2-D01/CP2-D02.**
Nenhuma tabela desta lista existe como resultado desta rodada. Nomes propostos nao sao
uma decisao aplicada, nem compromisso de criar toda a lista: sera necessario provar a
necessidade de cada tabela apos definir a estrutura e o escopo de autorizacao.
Antes da primeira migration, a ficha de cada tabela devera ser fechada com tipos, nulabilidade,
FKs, indices, estrategia de rollback e suas constraints verificadas no PostgreSQL de teste.

## Regras comuns derivadas da baseline

`Account` nativo e limite externo; `account_id NOT NULL` e FK de existencia nao bastam
para demonstrar que todas as referencias apontam para a mesma conta. Nao adicionar um
Tenant paralelo, RLS nao padronizado, default_scope global ou consulta unscoped operacional.

IDs internos numericos sao o padrao observado. Accounts/users/contacts/conversations usam
serial/integer; entidades modernas frequentemente usam bigint. Tipar novas referencias
conforme a tabela alvo, sem 'corrigir' as tabelas existentes. Nao gerar UUIDs ou numero
publico com MAX(id)+1. Nenhum endpoint publico foi autorizado que exija outro identificador.

As propostas abaixo usam Account+escopo autorizado, timestamps nativos e chaves de procura
por Account primeiro. Unicidades e nomes de indices sao fechados junto a cada migration.
A protecao SQL dos vinculos entre contas deve ser projetada e testada, nao presumida a partir
de validates. Qualquer indice adicional numa tabela nativa precisa de justificativa especifica
antes de implementacao; nenhum foi criado agora.

## Fichas conceituais

### 1. Escopos operacionais - estrutura depende de CP2-D01
- TABELA: alternativas, nao escolhidas: `jrc_service_desk_operating_companies` +
  `jrc_service_desk_operating_units` (A), ou estrutura plana/arvore (B/C).
- FINALIDADE: identificar quem opera o atendimento, separado de quem e cliente.
- ACCOUNT BOUNDARY: Account obrigatoria; parentela e todos os filhos na mesma conta.
- COLUNAS: id, account_id, identificador operacional, nome, estado ativo, timestamps;
  FK de operadora/unidade ou parentesco somente conforme decisao.
- FKs: Account; pai operacional somente se houver e com igualdade de Account.
- INDICES: procura por account_id; unicidade do identificador no escopo aprovado.
- RELACOES: tickets, filas, calendarios/condicoes aplicadas e vinculos de escopo.
- JUSTIFICATIVA: SD-D01; nenhuma Company/Organization reutilizada como operadora.
- BLOQUEIO: CP2-D01. Nenhuma unidade padrao/ficticia sera criada automaticamente.

### 2. Vinculos de escopo - estrutura depende de CP2-D02
- TABELA: possivel `jrc_service_desk_unit_memberships`, somente na alternativa A.
- FINALIDADE: restringir o escopo de dados sem duplicar papeis/permissoes.
- ACCOUNT BOUNDARY: AccountUser e unidade precisam da mesma Account.
- COLUNAS: id, account_id, account_user_id, unidade, estado/periodo de validade, timestamps.
- FKs: Account, AccountUser e unidade, condicionadas ao desenho aprovado.
- INDICES: unicidade de vinculo por Account/unidade/AccountUser e buscas de revogacao.
- RELACOES: pessoas/agentes nativos e escopo operacional; nao User novo.
- JUSTIFICATIVA: negacao de acesso entre unidades da mesma conta.
- BLOQUEIO: CP2-D01/D02. Sem roles, permissions ou RBAC paralelo nessa associacao.

### 3. Estados do chamado
- TABELA: possivel `jrc_service_desk_ticket_statuses`.
- FINALIDADE: identidade estavel de status e classificacao tecnica para o ciclo futuro.
- ACCOUNT BOUNDARY: configuracao e ticket sob mesma Account e escopo aplicavel.
- COLUNAS: id, account_id, chave, nome, posicao, ativo, familia tecnica, timestamps.
- FKs: Account; escopo opcional so depois de definir a configuracao por unidade.
- INDICES: (account_id, chave) unica no escopo final, ordenacao e busca por ativo.
- RELACOES: tickets e historico; nao status de Conversation reaproveitado.
- JUSTIFICATIVA: representar estados sem impor aos chamados o enum de Conversas.
- BLOQUEIO: propriedade de configuracoes e escopo dependentes de CP2-D01/D02.
  Regras de transicao, estados iniciais, cancelamento e reabertura nao foram implementados.

### 4. Prioridades
- TABELA: possivel `jrc_service_desk_priorities`.
- FINALIDADE: prioridade operacional do chamado, distinta de estado/categoria.
- ACCOUNT BOUNDARY: catalogo e chamado na mesma conta/escopo.
- COLUNAS: id, account_id, chave, nome, ordem, ativo, timestamps.
- FKs: Account; escopo conforme decisao.
- INDICES: chave unica por escopo; procura e ordenacao sob Account.
- RELACOES: tickets; referencia para politica aplicada futura, sem acionar calculo agora.
- JUSTIFICATIVA: nao modificar enum de prioridade de Conversas nem impor ranking do CRM.
- BLOQUEIO: CP2-D01/D02; escala e defaults nao sao dados de exemplo reais.

### 5. Categorias/classificacao
- TABELA: possivel `jrc_service_desk_categories`.
- FINALIDADE: classificacao dos tickets, sem duplicar cadastro de cliente/produto.
- ACCOUNT BOUNDARY: conta e escopo iguais ao ticket; parentesco, se aprovado, mesma conta.
- COLUNAS: id, account_id, chave, nome, ativo, timestamps; hierarquia nao presumida.
- FKs: Account; pais somente mediante necessidade documentada.
- INDICES: chave por escopo; procura por Account/ativo.
- RELACOES: tickets e classificacao; nao criar catalogo comercial paralelo.
- JUSTIFICATIVA: requisito de categoria/classificacao do CP2.
- BLOQUEIO: CP2-D01/D02; nenhuma taxonomia/setor foi hardcoded.

### 6. Filas de Service Desk
- TABELA: possivel `jrc_service_desk_queues`.
- FINALIDADE: representar fila operacional sem substituir Team ou fila de voz.
- ACCOUNT BOUNDARY: fila, escopo operacional e Team sob mesma Account.
- COLUNAS: id, account_id, escopo operacional, team_id quando aplicavel, nome/chave,
  ativo, timestamps; distribuicao automatica e capacidade fora desta rodada.
- FKs: Account, escopo aprovado e Team nativo; impedir combinacoes entre contas.
- INDICES: (account_id, escopo, chave), (account_id, team_id), ativos por escopo.
- RELACOES: tickets, Team/TeamMember; participacao nao e permissao implicita de unidade.
- JUSTIFICATIVA: requisito de equipe/fila do nucleo.
- BLOQUEIO: CP2-D01/D02 e propriedade da fila; nenhuma automacao/roteamento implementada.

### 7. Tickets
- TABELA: proposta `jrc_service_desk_tickets`.
- FINALIDADE: processo operacional distinto de Conversation.
- ACCOUNT BOUNDARY: Account confiavel do contexto; toda referencia resolvida no escopo
  autorizado, validada no model e protegida nas constraints que forem implementadas.
- COLUNAS: id, account_id, escopo operacional, titulo, descricao, solicitante Contact,
  responsavel nativo, fila/equipe, status, prioridade, categoria, origem/canal,
  lock_version e timestamps; marcos e snapshots em registro aplicado relacionado.
- FKs: Account, escopo, Contact, usuario/vinculo nativo e configuracoes; nenhuma FK de Projetos.
- INDICES: por Account/escopo + status, fila, responsavel, prioridade e created_at;
  idempotencia somente com contrato de comando definido, sem chaves artificiais por acaso.
- RELACOES: historico, comentarios, conversas e condicoes aplicadas; nao copiar Message.
- JUSTIFICATIVA: fonte unica futura de listagem/workspace/SLA, sem dashboard neste CP2.
- BLOQUEIO: CP2-D01/D02. Criar com escopo nulo seria contornar a decisao e nao sera feito.

### 8. Eventos de historico
- TABELA: possivel `jrc_service_desk_ticket_events`.
- FINALIDADE: registrar alteracoes relevantes e sua origem com antes/depois.
- ACCOUNT BOUNDARY: evento e ticket mesma Account; ator e contexto validados.
- COLUNAS: id, account_id, ticket_id, tipo, ator, origem, antes/depois JSONB,
  correlation_id quando houver e instante; sem conteudo secreto ou copia de arquivo.
- FKs: Account e ticket; ator/conservacao historica exigem politicas coerentes de ciclo de vida.
- INDICES: (account_id, ticket_id, created_at, id), tipo/tempo conforme consulta necessaria.
- RELACOES: ticket; evento nao constitui dispatcher, notificacao ou integracao ativa.
- JUSTIFICATIVA: historico operacional nao deve depender de alterar o EVENT_TYPES do CRM.
- BLOQUEIO: ticket e autoria dependentes; append-only exige teste real, nao so comentario Ruby.

### 9. Comentarios/notas de dominio
- TABELA: possivel `jrc_service_desk_ticket_comments`, apenas para comentario proprio do ticket.
- FINALIDADE: nota operacional separada das mensagens ja existentes nos canais.
- ACCOUNT BOUNDARY: ticket, ator e visibilidade limitados pela mesma Account/unidade.
- COLUNAS: id, account_id, ticket_id, autor nativo, corpo, visibilidade, timestamps.
- FKs: Account, ticket e autor conforme regra historica; sem identidade de portal antecipada.
- INDICES: (account_id, ticket_id, created_at, id).
- RELACOES: ticket, historico e Active Storage quando aplicavel.
- JUSTIFICATIVA: notas internas sao dominio; resposta por canal continua em Message.
- BLOQUEIO: CP2-D01/D02. Nao criar envio publico, portal, notificacao ou publicacao implicita.

### 10. Condicoes de SLA/contrato/calendario aplicadas e marcos
- TABELA: possivel familia `jrc_service_desk_sla_instances`/snapshots versionados;
  normalizacao final somente com necessidade comprovada e desenho fechado.
- FINALIDADE: preservar condicoes efetivamente aplicadas e marcos de primeira resposta/resolucao.
- ACCOUNT BOUNDARY: snapshot, ticket, calendario e escopo operacional compativeis.
- COLUNAS: id, account_id, ticket_id, versao local, referencia/versao externa, condicoes
  necessarias JSONB, versao/calendario/timezone explicitos, captura/aplicacao, marcos/prazos.
- FKs: Account, ticket e versoes locais reais; ID externo nao vira FK para tabela ficticia.
- INDICES: versao por ticket/Account unica; prazos por Account/escopo para consulta futura.
- RELACOES: ticket e registros de pausas caso necessarios.
- JUSTIFICATIVA: SD-D02/SD-D04; conservar o compromisso anterior quando fonte mudar.
- BLOQUEIO: propriedade do ticket; precedencia/defaults/fallback nao inventados.
  Registro pendente/sem calculo nao pode ser exibido como prazo calculado ou SLA cumprido.
  Nenhum calculador, calendario visual, integracao externa ou SLA operacional foi criado.

### 11. Intervalos de pausa, se necessarios ao contrato de marcos
- TABELA: possivel `jrc_service_desk_sla_pauses`.
- FINALIDADE: registrar intervalo e motivo sem reescrever snapshot ou contadores sem origem.
- ACCOUNT BOUNDARY: chamado/SLA/pausa mesma Account e escopo.
- COLUNAS: id, account_id, instancia/ticket, inicio, fim, motivo, ator, timestamps.
- FKs: Account e instancia aplicada; consistencia entre instancia e ticket obrigatoria.
- INDICES: consulta por instancia/tempo; evitar dois intervalos abertos simultaneamente.
- RELACOES: SLA aplicado; nenhum job de recalculo nesta rodada.
- JUSTIFICATIVA: somente se o marco precisar representar suspensao; nao criar sem necessidade.
- BLOQUEIO: dominio aplicado e regras de pausa; sem inferir que pendente significa pausado.

### 12. Vinculos com conversas
- TABELA: possivel `jrc_service_desk_ticket_conversations`.
- FINALIDADE: ligar o processo a conversas nativas, sem copiar mensagens ou criar envio.
- ACCOUNT BOUNDARY: ticket e Conversation na mesma Account; acesso exige tambem politica
  nativa da conversa, nao apenas saber o conversation_id.
- COLUNAS: id, account_id, ticket_id, conversation_id, origem do vinculo, timestamps.
- FKs: Account, ticket e Conversation, consistencia entre contas obrigatoria.
- INDICES: unicidade do par por Account; consultas reversas por conversa.
- RELACOES: ticket e conversas; usar ID interno, nao confundir com display_id ou uuid.
- JUSTIFICATIVA: fronteira explicita para futuro workspace multicanal, sem integracao ativa agora.
- BLOQUEIO: CP2-D01/D02 e controle de acesso dos dois dominios.

## Anexos: reutilizacao, nao nova infraestrutura de blobs

Active Storage existe e devera ser reutilizado. Nenhuma tabela de blobs/attachments paralela
esta proposta. O model Attachment atual exige Message: nao sera repurposed para um ticket.
A autorizacao de criar/ler um vinculo precisa validar ticket/nota, Account e visibilidade;
nao aceitar blob_id ou URL assinada como prova suficiente de propriedade.
Nenhum endpoint de upload/download ou mudanca nas rotas Active Storage foi criado.

## Fronteira futura Service Desk -> Projetos

Somente contrato documental: vinculo/evento com dominio de origem explicito, Account,
identificadores internos, escopo operacional autorizado, versao, correlation_id e idempotencia.
Validar ambos os dominios e suas flags no momento da integracao; nao copiar tickets, tarefas
ou mensagens. Ausencia de Projetos nao impede isolamento/funcionamento futuro do Service Desk.
Nao ha tabela de vinculos genericos, project_id, polimorfismo livre, model, flag, dependencia,
rota, frontend ou implementacao operacional de Projetos nesta rodada.
