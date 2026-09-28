# CP6 atualizado - validacao nativa acumulada

**PENDENTE — validação nativa em Docker/servidor**

CP6-D01 aprovada e implementada; executar tambem os quatro specs novos de inicializacao/estrutura e os dois Vitest de estrutura. Nenhuma migration nova.

```sh
RAILS_ENV=test bundle exec rspec spec/services/jrc_service_desk/initialize_account_service_spec.rb spec/services/jrc_service_desk/structure_service_spec.rb spec/requests/api/v1/accounts/jrc_service_desk/structure_spec.rb spec/requests/super_admin/service_desk_initializations_spec.rb
pnpm exec vitest run app/javascript/dashboard/routes/dashboard/serviceDesk/__tests__/structureContracts.spec.js app/javascript/dashboard/routes/dashboard/serviceDesk/__tests__/structureView.spec.js
```

Conferir antes a conexao real do banco de teste. Testar transacao/idempotencia/CSRF/autoridade/revogacao/F5. Configurar designacao somente para pessoas reais verificadas no destino, nunca para atores das fixtures.

O roteiro atualizado tem 15 fases e 84 casos manuais. As instrucoes abaixo sobre CP6-D01
ainda pendente de decisao sao HISTORICAS e foram substituidas pela aprovacao e implementacao
registradas em CP6_D01_APROVADA.md. As demais dependencias nativas continuam pendentes.

## Roteiro anterior acumulado (contexto historico)

# CP6 - validacao nativa acumulada

**PENDENTE — validação nativa em Docker/servidor**

CP1 a CP5 continuam com os resultados nativos pendentes. CP6 acrescenta codigo e testes, mas nao inicializou Rails/ActiveRecord/SQL/Vue nem aplicou migration. As suites isoladas e o gravador de declaracoes nao equivalem a essas provas.

As tentativas desta rodada encontraram Ruby3.3.8, Node22.16.0 e Bundler2.5.22; o projeto exige Ruby3.4.4, Node24.13.0, Bundler2.5.16 e pnpm10.2.0. Rails/RSpec/pnpm/Docker/psql nao ficaram disponiveis. bundle3.3 check rejeitou a versao Ruby. Nao alteramos manifests ou lockfiles. O Dockerfile somente fixa a tag Node na versao ja declarada e exige pnpm frozen.

## Execucao posterior

Usar `JRC-SERVICE-DESK-ROTEIRO-HOMOLOGACAO.md`:15 fases,75 casos manuais e formulario por linha da matriz de246controles/acoes. Nao executar suites antes de conferir destino: POSTGRES_DATABASE e DATABASE_URL podem apontar RAILS_ENV=test para um banco incorreto. Separar laboratorio manual, banco RSpec descartavel e banco exclusivo para concorrencia.

CP6-D01 impede provisionamento estrutural novo e concessao inicial de membership. Sem estrutura previamente autorizada, os testes manuais dependentes ficam PENDENTE FUNCIONAL, nao apenas pendentes de runtime. As factories somente criam dados no banco exclusivo de testes; nao representam bootstrap operacional.

## Novos specs nativos

- spec/requests/api/v1/accounts/jrc_service_desk/configuration_spec.rb
- spec/services/jrc_service_desk/configuration_service_spec.rb
- spec/services/jrc_service_desk/configuration_concurrency_spec.rb
- spec/services/jrc_service_desk/cp6_history_visibility_spec.rb
- app/javascript/dashboard/routes/dashboard/serviceDesk/__tests__/configurationContracts.spec.js
- app/javascript/dashboard/routes/dashboard/serviceDesk/__tests__/configurationViews.spec.js

Esses arquivos foram escritos e verificados sintaticamente, NAO executados pelo RSpec/Vitest. A suite de concorrencia e opt-in e usa fixtures commitadas em OUTRO banco descartavel. Skip nao e aprovacao. Specs anteriores preservados.

## Novos testes isolados

- spec/isolated/jrc_service_desk_configuration_test.rb:10testes/94assercoes.
- spec/isolated/jrc_service_desk_history_projection_test.rb:6testes/50assercoes.
- configurationCases.js:48casos compartilhados pelo runner Node e pelo spec Vitest; somente Node isolado foi executado.

Com os casos anteriores:74testes Ruby/1.431assercoes e317casos Node, sem falhas. Usam doubles de dados/transportes exclusivos de testes. Nao comprovam constraints ou transacoes SQL, autenticacaoHTTP, tzinfo real, montagemVue ou F5.

## Ensaios indispensaveis

Aplicar tres migrations acumuladas, carregar namespaces, executar RSpec completo afetado, validar constraints/locks e auditoria nativa associada a Unit, compilar/lint/testar Vue, conferir idempotencia e revisao, proteger campos de historico, CRUD ativo/inativo, ciclo versionado e snapshot real, KPIs por SQL, revogacao em sessao, respostas antigas, F5 e regressao nativa.

Nenhuma classificacao funcional foi promovida a sucesso por ausencia de execucao. Projetos e outro checkpoint nao foram iniciados.
