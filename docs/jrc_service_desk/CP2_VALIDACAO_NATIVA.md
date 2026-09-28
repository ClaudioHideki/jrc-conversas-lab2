# CP2 - validacoes nativas pendentes

**PENDENTE — validação nativa em ambiente Docker/local**

Nenhum Rails/ActiveRecord/RSpec/Featurable/Vitest foi considerado aprovado. Nenhuma migration
foi aplicada neste ambiente. Minitest isolado e gravacao da DSL nao sao testes de banco.
As pendencias do CP1 permanecem e devem ser executadas junto do CP2.

## Ambiente

Usar copia isolada do JRC em Docker/local, Ruby 3.4.4, Node 24.13.0, Bundler 2.5.16,
pnpm 10.2.0 e as dependencias EXATAS dos lockfiles. PostgreSQL/Redis exclusivos de teste.
Nao alterar runtimes, Gemfile, manifests, lockfiles ou configuracoes para mascarar falhas.
Nao usar dados reais; nenhum comando abaixo autoriza apagar um banco existente.

## Sequencia de verificacao no container/local Linux correto

Confirmar conexao de teste isolada e backup antes de preparar schema. Nao rodar o rollback
com dados para apagar historico. O core recusa rollback se qualquer tabela tiver registros.
Aplicar migrations pelo Rails (o schema.rb deste ZIP ainda e o CP1, propositalmente nao editado):

```sh
RAILS_ENV=test bundle exec rails db:migrate
```

O Rails deve gerar/atualizar o schema automaticamente no ambiente de validacao. Guardar esse
diff e verificar as 13 tabelas/4 indices auxiliares/45 FKs/23 CHECKs. A segunda migration cria
46 indices do modulo. Nao criar tabelas manualmente a partir do gravador de DSL.

```sh
RAILS_ENV=test bundle exec rails zeitwerk:check
```

```sh
RAILS_ENV=test bundle exec rails runner 'puts [Rails.version, ActiveRecord.version, JrcServiceDesk::Ticket.table_name].inspect'
```

```sh
RAILS_ENV=test bundle exec rspec spec/models/jrc_service_desk spec/policies/jrc_service_desk spec/services/jrc_service_desk spec/migrations/jrc_service_desk_core_spec.rb spec/controllers/api/v1/accounts/jrc_service_desk/base_controller_spec.rb spec/models/concerns/jrc_service_desk_feature_spec.rb spec/models/concerns/featurable_spec.rb
```

```sh
pnpm exec vitest run app/javascript/dashboard/__tests__/serviceDeskFeatureFlag.spec.js
```

## Cobertura obrigatoria

Models/relacoes/validacoes, operadora/unidade/AU/contato/ticket de outra Account, unidade
sem grant mesmo para administrador, atribuicao cross-unit, IDs manipulados, flag desligada,
revogacao, roles customizados negados, notas internas, ACL nativa de conversa e snapshots.
Verificar insert_all! em testes de constraints (bypass proposital de validacao para testar FK),
rollback vazio em banco descartavel separado e recusa do rollback com dados.

Concorrencia real adicional: duas criacoes com a mesma chave; payload conflitante; notas/
snapshots concorrentes; atualizacao otimista; revogacao de grant/flag durante comandos.
Medir contencao de locks por unidade. Esses cenarios simultaneos NAO foram executados aqui.

Smoke/regressao: Cockpit/jrcService, Email/Calls Center, CRM, Campanhas, NICO, Calling,
Conversas/canais, usuarios/autenticacao/permissoes; preservar 71 flags anteriores e flag SD
false. Testar exclusao/merge nativos que agora possam ter referencias SD, sem perder historico.
Sem rotas CP2 nesta entrega: verificar base HTTP do CP1 e ausencia de novos endpoints; a API
operacional futura nao deve ser declarada testada ou existente.

## Resultado a registrar

Para cada comando/cenario: runtime real, codigo de saida, exemplos/falhas, logs redigidos sem
credenciais, hash do pacote testado e diff do schema gerado pelo Rails. Ausencia de teste nao
e aprovacao. Nao iniciar CP3 automaticamente.
