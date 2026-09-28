# CP4 - validacao nativa acumulada

PENDENTE — validação nativa em ambiente Docker/local

Roteiros CP1/CP2/CP3 e specs anteriores foram preservados. Esta entrega nao executou Rails, RSpec, ActiveRecord, Featurable, SQL, migrations, Vue/Vitest, lint nativo ou build. Os comandos tentados falharam antes da suite: bundle/pnpm ausentes; Docker tambem ausente. Ruby disponivel 3.3.8 e Node 22.16.0 diferem dos requisitos 3.4.4/24.13.0. Nenhuma versao, lockfile ou requisito foi alterado.

## Ambiente isolado

Usar Ruby 3.4.4, Node 24.13.0, Bundler 2.5.16, pnpm 10.2.0 e dependencias dos lockfiles. PostgreSQL e Redis de teste exclusivos. Confirmar destino e backup. Migrations CP2 precisam ser aplicadas pelo Rails; schema.rb permanece intacto e nao foi editado manualmente.
Unidade, operadora, classificacao, status inicial e UnitMembership precisam existir por configuracao explicitamente autorizada; o CP4 nao provisiona nem habilita flag automaticamente.

## Suites

```sh
RAILS_ENV=test bundle exec rails zeitwerk:check
RAILS_ENV=test bundle exec rspec spec/requests/api/v1/accounts/jrc_service_desk spec/models/jrc_service_desk spec/policies/jrc_service_desk spec/services/jrc_service_desk spec/serializers/jrc_service_desk spec/migrations/jrc_service_desk_core_spec.rb spec/controllers/api/v1/accounts/jrc_service_desk/base_controller_spec.rb spec/models/concerns/jrc_service_desk_feature_spec.rb spec/models/concerns/featurable_spec.rb
pnpm exec vitest run app/javascript/dashboard/routes/dashboard/serviceDesk/__tests__ app/javascript/dashboard/__tests__/serviceDeskFeatureFlag.spec.js
pnpm exec eslint app/javascript/dashboard/routes/dashboard/serviceDesk app/javascript/dashboard/api/serviceDeskOperations.js app/javascript/dashboard/api/serviceDeskOperationsClient.js
pnpm exec vite build
```

Nao copiar esses comandos para um banco existente sem confirmar o ambiente correto. Aplicacao de migrations e rollback vazio seguem o roteiro CP2; nenhum rollback automatico ou destrutivo e fornecido aqui.

## Concorrencia real opt-in

`cp4_concurrency_spec.rb` possui duas provas com conexoes PostgreSQL simultaneas: mesma chave/mesmo payload cria um ticket; mesma chave/payload conflitante rejeita um. Nao executado. Requer `JRC_SD_CONCURRENCY=1`, Rails test, conexoes disponiveis e banco DESCARTAVEL separado, pois precisa de fixtures commitadas. Rodar esse arquivo isoladamente. Nao remove dados nem assume permissao para limpar um banco; descartar o banco dedicado pelo procedimento autorizado do ambiente depois.
Sem opt-in, a suite o marca skip/PENDENTE, nunca aprovado. Ainda ensaiar revogacao simultanea, deadlocks, leitura durante alteracao e throughput por unidade.

## Criterios funcionais reais a registrar

Criar -> ID real -> detalhe -> lista -> fila -> F5 -> mesmo registro. Editar/atribuir/status open/nota/vinculo -> commit -> GET -> UI -> F5. Nota e vinculo precisam aparecer e ser relidos pelo proprio ID, nao so pelo ticket.
Duas Accounts, duas unidades, admin sem grant, grant revogado, unidade inativa, flags false, responsavel de outra unidade, IDs manipulados, versao obsoleta, chave repetida/conflitante, falhas da API e paginas alem do fim.
KPIs: executar fixtures 27=8+12+7, mutacao controlada de registro e comparar 27=7+12+8, scopes, filtros, total independente da pagina e agrupamento por fase. A fixture que muda para resolved nao e aprovacao do fluxo resolver, bloqueado em CP4-D01.
Reabrir navegador/recarregar nao pode recuperar dados somente do Vue. Inspecionar navegacao, estados de erro/403/404, PT/PT-BR/EN, responsividade, teclado, novos eventos, limpeza apos troca de usuario/Account e nenhuma mensagem falsa de sucesso.
Regressao: Cockpit/jrcService, Conversas/canais, CRM, Campanhas, NICO, Calling, Email/Calls Center, contatos, empresas, auth, flags. Riscos CP2 de exclusao/merge/retencao continuam; o CP4 nao mudou suas constraints.

## Testes realmente executados nesta rodada

15 testes Minitest/520 assercoes sobre Input/QueryParameters/KpiCounts reais: zero falhas/erros/skips. Nao sao Rails/SQL.
57 testes Node CP4 sobre os clientes, decodificadores e state machine reais: zero falhas/skips. Nao montam Vue nem usam API real.
100 casos Node CP3 preservados: zero falhas/skips. Specs Vitest e RSpec escritos continuam sem execucao nativa.
Parsing e integridade sao evidencias parciais, nao prova de fluxo funcional completo.
