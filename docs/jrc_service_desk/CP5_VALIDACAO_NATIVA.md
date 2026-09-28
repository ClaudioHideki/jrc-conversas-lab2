# CP5 - pendencias nativas acumuladas

**PENDENTE — validação nativa em ambiente Docker/local**

## Ambiente e preservacao

As verificacoes isoladas e de integridade nao aprovam Rails, ActiveRecord, RSpec, SQL,
Featurable, TZInfo, Vue/Vitest, ESLint, Vite, interface ou servidor. CP1..CP4 permanecem
pendentes. CP6 nao iniciado.

Usar Ruby 3.4.4, Node 24.13.0, Bundler 2.5.16, pnpm 10.2.0 e dependencias dos lockfiles.
PostgreSQL/Redis de teste exclusivos. Conferir destino e backup. Nenhum comando autoriza
reset/drop ou remocao de dados existentes. Migrations CP2/CP4 precisam ser executadas no
destino; Rails deve gerar schema, nunca edita-lo manualmente. CP5 nao tem migration.

## Comandos propostos, NAO aprovados neste ambiente

```sh
RAILS_ENV=test bundle exec rails zeitwerk:check
RAILS_ENV=test bundle exec rails runner 'puts [Rails.version, ActiveRecord.version, JrcServiceDesk::Capabilities::KEYS.size].inspect'
RAILS_ENV=test bundle exec rspec spec/requests/api/v1/accounts/jrc_service_desk spec/models/jrc_service_desk spec/policies/jrc_service_desk spec/services/jrc_service_desk spec/serializers/jrc_service_desk spec/migrations/jrc_service_desk_core_spec.rb spec/controllers/api/v1/accounts/jrc_service_desk/base_controller_spec.rb spec/models/concerns/jrc_service_desk_feature_spec.rb spec/models/concerns/featurable_spec.rb
pnpm exec vitest run app/javascript/dashboard/routes/dashboard/serviceDesk/__tests__ app/javascript/dashboard/__tests__/serviceDeskFeatureFlag.spec.js
pnpm exec eslint app/javascript/dashboard/routes/dashboard/serviceDesk app/javascript/dashboard/api/serviceDeskNative.js app/javascript/dashboard/api/serviceDeskNativeClient.js app/javascript/dashboard/composables/useServiceDeskNavigation.js app/javascript/dashboard/components-next/sidebar/Sidebar.vue app/javascript/dashboard/routes/dashboard/settings/customRoles/component/CustomRoleModal.vue
pnpm exec vite build
```

Executar tambem suites nativas CustomRole, AccountUser audit, formulario de roles e Sidebar.
Registrar comando, runtime, exit code, exemplos/falhas/skips e hash do pacote. Skip por
extensao ausente nao e aprovacao dessa integracao. Nao suprimir falhas de regressao.

## Cenarios obrigatorios

1. Flag false oculta modulo, nega deep links/APIs e evita consulta operacional da sidebar.
   Nenhuma role liga a flag; 71 flags anteriores e default SD preservados.
2. Revogacao de flag/membership/capacidade: proxima API nega; foco/visibilidade/timer limpam
   dados. Troca de Account/usuario e respostas atrasadas nao repovoam o novo contexto.
3. Admin com/sem membership; Team sem membership; Account/operadora/unidade/AccountUser
   estrangeiros; CustomRole estrangeiro/invalido; membership mas sem capacidade de acao.
4. PATCH misto de titulo e prioridade sem a capacidade exigida nao faz escrita parcial.
   Prioridade isolada nao permite titulo. Criacao com atribuicao ou conversa exige essas
   capacidades; replay nao reativa uma permissao revogada.
5. Atribuicao/transferencia de outra unidade/Account, responsavel sem tickets_view e IDs
   manipulados devem negar. Locks e revogacao concorrente de CustomRole exigem ensaio SQL.
6. Resolver nao concede cancelar, fechar ou reabrir. Politica de outra unidade e publicacao
   sem capacidade devem negar. Versoes vinculadas e calendario CP4-D01 preservados.
7. Contact/Company/conversa de outra Account; ACL nativa revogada entre lista e clique;
   navegue por display_id, nao PK; nenhuma duplicacao de clientes/mensagens.
8. Historico, notas, SLA, condicoes brutas e cliente separados. Historico de vinculo redige
   IDs quando falta permissao de conversa. Arquivos nao recebem URLs indevidas.
9. Dois usuarios/unidades enxergam KPIs legitimamente diferentes. Scope igual a lista;
   total=sum(familias); ativos=open+waiting; atualizar dados controlados e conferir SQL/UI.
10. Auditoria real de autor/timestamp/Account/unidade/versao, transferencia e roles. Log
    nativo de role e Account-level. Alteracao custom_role_id auditada quando extensao existe.
11. Exclusao de role preserva fallback nativo: usar membership para revogacao total. Nao
    presumir concessao/estrutura automatica. Sem extensao, nao inventar RBAC substituto.
12. POST -> GET -> interface -> F5. Rejeicoes 403/404, loading/error/empty, voltar/deep links,
    PT-BR/PT/EN, teclado, responsividade e editor JSON. Sem confirmacao visual ficticia.
13. Regressao de Conversas, Cockpit, CRM, Campanhas, NICO, Calling, Email/Calls Center,
    Contatos, Empresas, autenticacao e CustomRoles; FKs/merge/exclusao dos checkpoints anteriores.

As suites opt-in de concorrencia CP4 precisam de banco descartavel independente e fixtures
commitadas. Seguir seus roteiros; nao foram executadas nesta rodada. Tambem medir bloqueios
por unidade, revogacao simultanea, queries adicionais e memoria nos lookups por registro.

## Pendencias funcionais explicitas

CRUD completo das configuracoes de filas/categorias/prioridades/status, bootstrap da
estrutura/memberships, anexos, envio por canal, first_response real, portal, relatorios
completos e governanca/comunicacao NICO permanecem pendentes. Uma permissao ou tela de
referencia nao equivale a fluxo entregue. Nenhuma dessas limitacoes foi simulada.

## Ambiente observado

Ruby 3.3.8, Node 22.16.0 e Bundler 2.5.22 disponiveis. bundle/pnpm/Docker/psql e executaveis
Rails/RSpec do projeto indisponiveis. bundle3.3 check recusou Ruby diferente do 3.4.4
exigido. Nenhum requisito, manifest ou lockfile foi alterado. Tentativas ficaram registradas
antes das suites; nenhum resultado ausente recebeu aprovacao.
