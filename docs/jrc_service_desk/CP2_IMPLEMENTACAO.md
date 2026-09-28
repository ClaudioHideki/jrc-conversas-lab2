# Checkpoint 2 - fundacao de dados e dominio implementada

**CP2 IMPLEMENTADO PARA REVISAO - VALIDACAO NATIVA PENDENTE.**
Registro de 25/09/2026. Nenhum CP3 iniciado. Nenhum frontend/rota operacional criado.
As migrations foram ESCRITAS, nao aplicadas a um banco neste ambiente. Nao confundir esta
fundacao com o Service Desk completo nem com fluxos visuais funcionando.

## Continuidade e decisoes

Baseline unica: `JRC-CONVERSAS-SERVICE-DESK-CP1-CONSOLIDADO-20260925.zip`.
SHA-256: `657a589816a52e4e0c8d18c20733540269ff638581a072e31b0e74534925ffe4`.
Os cinco documentos preparatorios anteriores foram recuperados integralmente da entrega
anterior, conferidos por hash e continuados; nao houve aplicacao de patch ao codigo nem
reconstrucao do CP1. O inventario previo foi preservado, nao substituido.
CP2-D01 e CP2-D02: APROVADAS, opcao A. Registro formal precedeu models/migrations.
SD-D01 a SD-D05: preservadas. Nenhuma CP2-D03+ pendente nesta rodada.
Detalhes tecnicos de nomes de classes, indices e FKs implementam as decisoes, sem outro RBAC.

## Estrutura implementada

Account -> OperatorCompany -> Unit. Ticket tem unit_id NOT NULL; operadora derivada da
unidade, nao armazenada redundantemente. Nenhuma unidade ficticia/default ou ticket sem unidade.
UnitMembership liga AccountUser nativo e Unit; active default FALSE, sem roles/permissoes.

Todos os registros operacionais possuem Account. As referencias entre entidades do modulo
incluem Account/unidade; referencias nativas incluem Account. Models validam coerencia e
migrations acrescentam FKs compostas para tambem rejeitar referencias incoerentes no banco.
Nao ha default_scope global, RLS novo, tenant paralelo ou alteracao das PKs existentes.

Statuses, prioridades, categorias e filas sao registros configuraveis por unidade. Status
usa familias tecnicas open/waiting/resolved/closed/cancelled; nomes/codigos nao sao seeded.
A criacao exige status inicial ativo configurado, prioridade e Contact solicitante explicitos.
Team e fila organizam roteamento; nenhuma das duas concede acesso a unidade.

## Banco: duas migrations aditivas

1. `20260925190000_add_jrc_service_desk_reference_keys.rb`: quatro indices UNIQUE
   (account_id,id), CONCURRENTLY, em account_users, contacts, teams e conversations.
   Justificativa: chaves alvo das FKs compostas. Nenhuma coluna/registro/model nativo alterado.
   Falha/interrupcao com indice invalido nao e ocultada; requer inspecao antes de retentar.
2. `20260925190100_create_jrc_service_desk_core.rb`: 13 tabelas, 46 indices do modulo,
   45 FKs e 23 CHECKs. Esses numeros sao da declaracao da migration, NAO de banco migrado.

Tabelas: operator_companies, units, unit_memberships, ticket_statuses, priorities, categories,
queues, tickets, ticket_events, ticket_notes, sla_snapshots, sla_milestones e
 ticket_conversations; todas com prefixo `jrc_service_desk_`.
A ficha de CADA tabela, com finalidade/Account/colunas/FKs/indices/relacoes/justificativa,
foi registrada em `CP2_MODELO_DE_DADOS.md` ANTES das migrations.

Todas as 201 migrations anteriores e db/schema.rb permanecem byte a byte iguais.
Aplicar migrations em Docker/local de teste e deixar Rails gerar o schema; nao editar a mao.
O schema.rb incluido ainda representa CP1: carregar somente esse schema nao cria o CP2.
Rollback do core somente aceita tabelas vazias. Se qualquer tabela CP2 contem dados,
levanta IrreversibleMigration antes de apagar a primeira. Nada executa rollback automaticamente.
Os quatro indices auxiliares so podem ser removidos depois de retirar suas FKs dependentes.

## Autorizacao e servicos

OperationalContext recebe SOMENTE objetos do contexto autenticado nativo, reconsulta
Account/User/AccountUser e verifica feature/conta/membership. IDs de parametros nunca autenticam.
Pundit decide a acao; consultas por TicketPolicy::Scope e scopes derivados combinam Account,
unidades ativas com vinculo explicito ativo e visibilidade do registro.

Administrador tem acesso apenas as unidades explicitamente vinculadas, sem bypass.
Agente nativo precisa adicionalmente ser criador, responsavel ou membro da equipe do ticket
DENTRO da unidade autorizada. Equipe em unidade sem vinculo nao concede acesso.
Sem nenhuma unidade ativa vinculada, permissoes de listagem tambem sao negadas.
Papeis customizados existentes nao possuem concessao Service Desk e permanecem negados;
nao se emprestam permissoes de Conversas/CRM e nao se altera o catalogo nativo no CP2.
Uma futura extensao compativel de capacidades pertence a etapa autorizada de permissoes.

UnitMembershipPolicy nega autoconcessao/administracao. Nao ha comando/API de bootstrap ou
provisionamento implicito. Nenhum usuario real recebeu unidade ou flag neste ambiente.
Policies de configuracao permitem leitura operacional e administracao nativa restrita a
unidade; nao ha endpoints ou comandos de administracao expostos nesta etapa.

Sete comandos internos implementados:
- CreateTicketService: validacao estrita, unidade/status/solicitante, origem manual,
  autor do contexto, idempotencia e evento na mesma transacao.
- FindTicketService: lookup dentro do scope Pundit autorizado.
- UpdateTicketService: titulo/descricao/prioridade/categoria; versao otimista e historico.
- AssignTicketService: AccountUser com grant ativo NA MESMA unidade, equipe/fila coerentes.
- AddNoteService: nota exclusivamente interna, autoria do contexto, deduplicacao e historico.
- LinkConversationService: referencia a Conversation da mesma Account E autorizacao nativa
  da conversa independente; nao copia mensagens, nao envia nada.
- RecordSlaSnapshotService: evidencia de condicoes explicitas, versionamento local, digest
  canonico e dois marcos pendentes; sem cliente HTTP, calendario mestre ou calculador.

Entradas usam allowlists e IDs inteiros positivos estritos. account_id, operator_company_id,
unit_id dentro do payload de atributos e campos de sistema nao sao aceitos como autoconcessao.
CreateTicket aceita unit_id apenas como seletor validado dentro das unidades autorizadas.
Update nao permite transicionar status, transferir unidade ou encerrar chamado por PATCH generico.
Transicoes completas continuam na etapa de fluxos, nao foram simuladas no CP2.

Mutacoes usam transacao, lock otimista e locks de linhas de identidade/grants; escritas da
mesma unidade sao serializadas nesta fundacao. Conflitos de chave de idempotencia rejeitam
payload diferente. Falha do evento desfaz a mutacao. Nenhum listener/job existente foi alterado.

## Historico, notas, anexos e SLA

Eventos armazenam valores antes/depois relevantes e autoria. Eventos/notas/snapshots/links
persistidos sao readonly no DOMINIO ActiveRecord e nao possuem comando publico de alteracao.
Nao se declara imutabilidade contra SQL direto, update_all ou um operador privilegiado de banco.
Nao foram adicionados triggers SQL nem mudanca global de schema_format.

Notas internas usam `has_many_attached :files` do Active Storage nativo. Nao existe ainda
comando de upload/download; `files`, blob_id e signed_id sao rejeitados pelas allowlists.
Nao emitir URLs ou reutilizar blobs sem autorizacao do registro/conta na futura camada API.
A associacao isolada nao equivale a uma funcionalidade de anexos concluida.

Snapshots preservam origem/versao externa, condicoes de contrato/SLA/calendario, timezone
IANA explicita, captura e aplicacao local, versao e SHA-256 canonico. Timestamps da captura
sao normalizados em UTC para deduplicar o mesmo instante. Objetos JSON sao limitados e
campos de credenciais conhecidos sao rejeitados; isso NAO e um detector completo de segredos.
Nenhumas condicoes sao buscadas externamente, nem a veracidade externa e certificada pelo CP2.

Cada snapshot cria marcos first_response/resolution SEM due_at, achieved_at ou calculo
ficticio. `met?` retorna nil enquanto faltam prazo/realizacao. Um prazo, quando registrado
futuramente, exige instante/versao do calculador. Snapshot de outro ticket e rejeitado.
Nao ha fallback 24x7, timezone/default de feriados, indicador ficticio nem alteracao no SLA
atual de Conversas. Condicoes financeiras brutas sao negadas ao agente pelo SnapshotPolicy.

TicketConversation exige tambem ConversationPolicy nativa para consultar/vincular. Listagem
indiscriminada de vinculos fica negada (Scope.none), pois o policy nativo nao fornece um
scope SQL equivalente para todos os canais. A exposicao de listas autorizadas e trabalho
da futura API, nao autorizacao para copiar dados de conversas.

## Fronteira futura com Projetos

Somente contrato: referencias deverao validar a mesma Account e escopos autorizados de ambos
os dominios; nunca copiar Tasks, mensagens ou cadastro de cliente. Nao ha tabela/model/flag/
rota/codigo de `jrc_projects`, nem FK especulativa `project_id` nesta entrega.

## Verificacoes executadas e limites

- Minitest isolado sobre os arquivos REAIS Input/CanonicalJson: 33 testes, 270 assercoes,
  zero falhas/erros. Nao carrega Rails/RSpec/SQL.
- Gravador isolado da DSL das migrations reais: 14 testes estruturais, 549 assercoes,
  zero falhas/erros. Verifica declaracoes/FKs/indices/ordem/guardas; NAO executa SQL nem
  demonstra que constraints foram aplicadas no PostgreSQL.
- Sintaxe Ruby, comparacao de arquivos/hashes, escopo e git diff --check registrados na
  evidencia da entrega. Nao substituem carregamento nativo ou regressao em navegador.

**PENDENTE - validacao nativa em ambiente Docker/local** para Rails, ActiveRecord, Zeitwerk,
RSpec, Featurable, Vitest, aplicacao/rollback vazio das migrations, constraints reais, locks,
concorrencia e smoke/regressao. O estado com acentuacao original consta tambem no roteiro nativo.
O ambiente oferece Ruby 3.3.8/Node 22.16.0; exige 3.4.4/24.13.0. Executaveis/dependencias
Rails/RSpec/pnpm/Docker estao ausentes. Nenhuma versao declarada ou lockfile foi alterado.
Os specs abaixo foram escritos e revisados estaticamente; NAO foram executados nativamente.

## Riscos de revisao e integracao futura

1. Validar primeiro o schema real no PostgreSQL/versao Rails do JRC. Nenhuma migration foi
   aplicada aqui, e o caminho de rollback com dados e intencionalmente bloqueado.
2. FKs restritivas podem impedir exclusao/merge de contatos, membros, equipes ou conversas
   enquanto houver historico SD referenciado. Isso protege integridade, mas os fluxos nativos
   de exclusao/merge/retencao precisam de smoke especifico antes de habilitar o modulo.
3. Serializacao por unidade simplifica concorrencia; medir throughput, deadlocks e revogacao
   simultanea antes de relaxar locks. Nenhum teste concorrente real foi executado aqui.
4. Nao retornar objetos ActiveRecord/JSON bruto diretamente numa futura API: aplicar policies,
   serializers e protecao por campo; snapshots financeiros e blobs nao acompanham uma permissao
   generica de leitura do ticket.
5. Catalogos/memberships nao sao provisionados automaticamente. Politicas atuais nao fazem
   autoconcessao nem atribuem capacidades Service Desk a roles customizados existentes.
6. Historia imutavel no dominio nao e garantia contra SQL privilegiado. Nao usar update_all/
   delete_all sobre eventos/snapshots; qualquer evolucao de retencao exige contrato proprio.

Nenhuma decisao humana nova foi criada: os riscos acima sao validacao/detalhamento de etapas
ja delimitadas, nao alteracoes silenciosas das aprovacoes CP2-D01/D02 ou SD-D01..SD-D05.

## Inventario executavel

### Models, bases e concern

```text
app/models/jrc_service_desk/account_record.rb
app/models/jrc_service_desk/append_only.rb
app/models/jrc_service_desk/category.rb
app/models/jrc_service_desk/named_unit_record.rb
app/models/jrc_service_desk/operator_company.rb
app/models/jrc_service_desk/priority.rb
app/models/jrc_service_desk/queue.rb
app/models/jrc_service_desk/sla_milestone.rb
app/models/jrc_service_desk/sla_snapshot.rb
app/models/jrc_service_desk/ticket.rb
app/models/jrc_service_desk/ticket_conversation.rb
app/models/jrc_service_desk/ticket_event.rb
app/models/jrc_service_desk/ticket_note.rb
app/models/jrc_service_desk/ticket_record.rb
app/models/jrc_service_desk/ticket_status.rb
app/models/jrc_service_desk/unit.rb
app/models/jrc_service_desk/unit_membership.rb
app/models/jrc_service_desk/unit_record.rb
```

### Services e validadores

```text
app/services/jrc_service_desk/add_note_service.rb
app/services/jrc_service_desk/assign_ticket_service.rb
app/services/jrc_service_desk/base_service.rb
app/services/jrc_service_desk/canonical_json.rb
app/services/jrc_service_desk/create_ticket_service.rb
app/services/jrc_service_desk/find_ticket_service.rb
app/services/jrc_service_desk/idempotency_conflict.rb
app/services/jrc_service_desk/input.rb
app/services/jrc_service_desk/link_conversation_service.rb
app/services/jrc_service_desk/operational_context.rb
app/services/jrc_service_desk/record_sla_snapshot_service.rb
app/services/jrc_service_desk/update_ticket_service.rb
```

### Policies e scopes

```text
app/policies/jrc_service_desk/category_policy.rb
app/policies/jrc_service_desk/configuration_policy.rb
app/policies/jrc_service_desk/operational_policy.rb
app/policies/jrc_service_desk/operator_company_policy.rb
app/policies/jrc_service_desk/priority_policy.rb
app/policies/jrc_service_desk/queue_policy.rb
app/policies/jrc_service_desk/sla_milestone_policy.rb
app/policies/jrc_service_desk/sla_snapshot_policy.rb
app/policies/jrc_service_desk/ticket_conversation_policy.rb
app/policies/jrc_service_desk/ticket_event_policy.rb
app/policies/jrc_service_desk/ticket_note_policy.rb
app/policies/jrc_service_desk/ticket_policy.rb
app/policies/jrc_service_desk/ticket_record_policy.rb
app/policies/jrc_service_desk/ticket_status_policy.rb
app/policies/jrc_service_desk/unit_membership_policy.rb
app/policies/jrc_service_desk/unit_policy.rb
```

### Specs CP2

```text
spec/migrations/jrc_service_desk_core_spec.rb
spec/models/jrc_service_desk/classification_spec.rb
spec/models/jrc_service_desk/history_and_sla_spec.rb
spec/models/jrc_service_desk/structure_spec.rb
spec/models/jrc_service_desk/ticket_spec.rb
spec/policies/jrc_service_desk/domain_policies_spec.rb
spec/policies/jrc_service_desk/ticket_policy_spec.rb
spec/services/jrc_service_desk/canonical_json_spec.rb
spec/services/jrc_service_desk/create_ticket_service_spec.rb
spec/services/jrc_service_desk/feature_gate_spec.rb
spec/services/jrc_service_desk/input_spec.rb
spec/services/jrc_service_desk/notes_and_links_services_spec.rb
spec/services/jrc_service_desk/operational_context_spec.rb
spec/services/jrc_service_desk/record_sla_snapshot_service_spec.rb
spec/services/jrc_service_desk/ticket_mutation_services_spec.rb
```

Factories e contexto de teste:
`spec/factories/jrc_service_desk.rb` e `spec/support/jrc_service_desk_context.rb`.
Dados de exemplo existem SOMENTE em testes; nao ha seed de dados operacionais, KPI ou mock de API.

**CP3 NAO INICIADO.** Esta entrega encerra somente a implementacao autorizada do CP2 para revisao.
