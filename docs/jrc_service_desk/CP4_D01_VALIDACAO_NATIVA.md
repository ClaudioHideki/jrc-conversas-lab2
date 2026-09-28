# CP4-D01 - validacao acumulada

**PENDENTE — validação nativa em ambiente Docker/local**

Roteiros e pendencias CP1/CP2/CP3/CP4 intermediario permanecem historicos e nao foram
considerados aprovados. O comando de transicao agora existe; as instrucoes antigas que
tratavam CP4-D01 como pendente de decisao foram superadas pela aprovacao e por este roteiro.

## Ambiente exigido

Ruby 3.4.4, Node 24.13.0, Bundler 2.5.16, pnpm 10.2.0, dependencias exatas dos lockfiles,
PostgreSQL e Redis de teste exclusivos. Conferir destino/backup antes de qualquer comando.
Nao alterar manifest/versoes/lockfile para mascarar falhas, nao usar dados reais.
Neste ambiente: Ruby 3.3.8, Node 22.16.0, Bundler 2.5.22; executaveis Rails/RSpec, pnpm,
Docker e psql indisponiveis. As tentativas foram registradas e falharam antes das suites.

## Comandos para ambiente correto (NAO executados aqui)

```sh
RAILS_ENV=test bundle exec rails db:migrate
RAILS_ENV=test bundle exec rails zeitwerk:check
RAILS_ENV=test bundle exec rails runner 'puts [Rails.version, ActiveRecord.version, JrcServiceDesk::LifecyclePolicy.table_name].inspect'
RAILS_ENV=test bundle exec rspec spec/requests/api/v1/accounts/jrc_service_desk spec/models/jrc_service_desk spec/policies/jrc_service_desk spec/services/jrc_service_desk spec/serializers/jrc_service_desk spec/migrations/jrc_service_desk_core_spec.rb spec/controllers/api/v1/accounts/jrc_service_desk/base_controller_spec.rb spec/models/concerns/jrc_service_desk_feature_spec.rb spec/models/concerns/featurable_spec.rb
pnpm exec vitest run app/javascript/dashboard/routes/dashboard/serviceDesk/__tests__ app/javascript/dashboard/__tests__/serviceDeskFeatureFlag.spec.js
pnpm exec eslint app/javascript/dashboard/routes/dashboard/serviceDesk app/javascript/dashboard/api/serviceDeskLifecycle.js app/javascript/dashboard/api/serviceDeskLifecycleClient.js
pnpm exec vite build
```

Esses comandos nao autorizam reset/drop/rollback ou uso de banco existente. Rails deve gerar
o schema no destino; o schema.rb entregue continua intacto. Conferir nova migration e 7
tabelas/19 indices/34 FKs/7 CHECKs/2 colunas de ticket. A migration so permite rollback vazio;
testar recusa com dados e rollback em OUTRO banco descartavel vazio, nunca limpar dados para passar.

## Cenarios obrigatorios

1. Sem politica aplicavel: GET sem acoes e POST negado. Politica especifica desabilitada nao
   usa default da unidade; politica ativa especifica tem precedencia; ticket antigo mantem versao.
2. Admin sem vinculo, agente de outra Account/unidade, grant revogado, flag false, IDs/adulteracao
   de service/policy/status/evidencia devem negar. UI local/admin role nao substitui API.
3. Publicacao nativa: GET apos POST confirma JSON/digest/version/nome/enabled/servico; repetir
   expected_version antigo gera conflito; versao anterior e eventos permanecem iguais.
4. Pausar com motivo e clocks selecionados; pausar com clocks:[]; status waiting sozinho;
   dupla pausa concorrente, motivo invalido, resume sem pausa, timestamps/autor reais.
5. Resolver sem requisitos falha atomicamente; com nota/solucao/evidencias/categoria/campos
   atende e persiste. Nota de outro ticket falha. false nao satisfaz equals:true.
6. Encerrar/cancelar somente por regra, sem job ou prazo automatico. Pausa aberta exige regra
   end_pause. Sem calendario/metas compativeis, nenhuma camada grava parcialmente.
7. Reabrir dentro/no limite/fora da janela; ancora inexistente; deny versus require_new_ticket;
   continue/count/exclude e new/same_snapshot/latest_snapshot; nenhum ticket automatico.
8. Timezone real/TZInfo/DST, feriados/excecoes, intervalos, virada do dia, prazo esgotado;
   nao inferir primeira resposta por nota interna. Snapshot antigo incompatvel bloqueia.
9. SQL direto invalidando account/unit/ticket deve falhar por constraint onde prevista;
   locks, idempotencia mesmo payload e chave conflitante; rollback transacional do evento.
10. POST -> GET transicao -> GET ticket -> GET lifecycle -> tela -> F5 -> mesmos dados.
    Simular falha de GET apos commit: sem sucesso falso, recuperar pela MESMA chave.
    Trocar Account limpa rascunho/dados e cancela respostas obsoletas.
11. KPI por SQL: 27=8+12+7 -> resolver um -> 27=7+12+8; Total=sum(familias),
    Ativos=open+waiting, filtros/permissoes identicos a lista, sem contador local.
12. Regressao: Cockpit/jrcService, Conversas, canais, CRM, Campanhas, NICO, Calling, Email/Calls,
    contatos, empresas, autenticacao, flags. Reavaliar exclusao/merge com FKs CP2.

## Concorrencia opt-in

lifecycle_concurrency_spec.rb requer JRC_SD_CONCURRENCY=1 e banco DESCARTAVEL exclusivo com
conexoes paralelas. Os dados de fixture precisam de commit, portanto rodar isoladamente e
nao na base real. Sem opt-in, skip significa PENDENTE. Nao fornece apagamento de dados.
Ainda medir throughput/locks por unidade, revogacao concorrente e eventual deadlock.

## Specs anteriores

Todos os specs antigos permanecem, sem remocao de exemplos. Dois foram atualizados somente
para a regra aprovada: operations_spec.rb e cp4_workflow_spec.rb publicam explicitamente a
politica work_status no teste positivo e verificam o novo evento de ciclo. Isso nao e uma
mudanca para contornar runtime ausente. Os demais specs CP1/2/3/4 nao foram alterados.

## Provas isoladas disponiveis

```sh
ruby spec/isolated/jrc_service_desk_lifecycle_test.rb
ruby spec/isolated/jrc_service_desk_clock_engine_test.rb
ruby spec/isolated/jrc_service_desk_lifecycle_migration_test.rb
```

Os testes usam fixtures/doubles declarados, nunca dados da aplicacao. Gravacao da DSL verifica
as declaracoes, nao SQL. Node isolado verifica clientes/decoders/state machine, nao Vue.
A matriz end-to-end permanece PENDENTE mesmo com esses checks passando.
