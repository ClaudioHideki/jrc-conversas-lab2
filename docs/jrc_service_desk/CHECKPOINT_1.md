# JRC Conversas - Checkpoint 1: infraestrutura/base do Service Desk

## Estado e limite

Execucao autorizada: SOMENTE Checkpoint 1. Nenhum checkpoint posterior esta autorizado.
Esta entrega introduz infraestrutura inativa, documentacao e testes; nao entrega chamados,
telas, menus, APIs operacionais, portal, SLAs operacionais ou Projetos.
SD-D01 a SD-D05 estao APROVADAS no CP1-R2 e registradas em `DECISOES_APROVADAS.md`.
`DECISOES_PENDENTES.md` preserva o historico anterior e aponta para o estado vigente.
Nao ha implementacao operacional autorizada: aprovar essas decisoes nao autoriza CP2.
A aprovacao tecnica depende tambem da evidencia de execucao dos testes no ambiente nativo;
nao confundir teste isolado com inicializacao do Rails ou homologacao.

## Base oficial e regras obrigatorias para todo o desenvolvimento futuro

1. A unica base oficial desta evolucao e `jrc-conversas-nico-v12-2-7-comercial-integrado-main (2)(1).zip`.
   SHA-256: `0e8d7e18e244ffef0e045d5c14428f2bc6702dacb9c4d508236a7fa292a1f7c4`.
   Trabalhar sobre sua copia; nunca substituir sua arquitetura pelos pacotes auxiliares.
2. Service Desk (`jrc_service_desk`) e Projetos (`jrc_projects`) sao dois modulos NOVOS,
   independentes e adicionais. `jrc_projects` esta apenas reservado em documento, sem codigo ou flag neste checkpoint.
3. Nenhum substitui Conversas, Cockpit/jrcService, CRM, Campanhas, NICO, Calling, E-mail,
   Contatos, Empresas, Help Center ou qualquer modulo existente. Preservar branding JRC.
4. Seguir Rails/Vue, Account, usuarios/agentes, equipes, contatos, empresas, autenticacao,
   Pundit, feature flags, Active Storage, eventos, jobs e padroes visuais nativos.
5. Nao fazer refatoracao geral, mudanca destrutiva, duplicacao de cadastro ou migration desnecessaria.
   Nao editar `db/schema.rb` manualmente. Nao reorganizar bits/colunas/defaults das flags anteriores.
6. Nao considerar concluida uma funcao sem a cadeia verificavel:
   frontend -> API -> autorizacao -> regra de negocio -> banco -> leitura -> interface -> KPI, quando aplicavel.
7. Proibidos numeros hardcoded, mocks apresentados como dados reais, graficos sem fonte e KPIs apenas visuais.
   Doubles/fixtures sao permitidos SOMENTE em testes claramente identificados, nunca como dados de producao.
8. Cada KPI futuro deve registrar fonte/consulta, conta e escopos, filtros, janela/fuso, formula,
   criterio de inclusao/exclusao e teste com alteracao controlada de registros, inclusive invalidacao de cache.
9. Cada botao futuro deve ser testado: criar -> persistir -> listar -> abrir -> atribuir ->
   mudar prioridade/status -> recalcular SLA/KPI -> filtrar -> sobreviver a refresh, quando aplicavel.
10. Decisao estrutural incerta exige `DECISAO PENDENTE`, alternativas, impacto e bloqueio explicito.
    Nao escolher silenciosamente o schema, a identidade externa ou as regras de acesso.
11. Avancar somente com autorizacao especifica do proximo checkpoint. ZIP candidato somente no checkpoint autorizado para isso.

## Infraestrutura implementada

| Parte | Implementacao | Limite |
|---|---|---|
| Dominio | `JrcServiceDesk` / `jrc_service_desk` | Nao e `jrcService` |
| Prefixo SQL | `jrc_service_desk_` | Nenhuma tabela criada |
| Base de models | `JrcServiceDesk::Base < ApplicationRecord`, abstrata, `belongs_to :account` obrigatorio | Sem schema, callbacks operacionais ou default_scope |
| Contexto | `JrcServiceDesk::AccessContext` | Recebe SOMENTE contexto confiavel nativo, nunca parametros do cliente |
| Disponibilidade | Account/User/AccountUser persistidos, IDs coerentes, conta ativa e flag estritamente true | Pre-requisito, nao permissao de acao |
| Politica | `JrcServiceDesk::BasePolicy < ApplicationPolicy` | Nega todas as acoes base, inclusive show?; nenhum bypass de admin |
| Scope | `resolve` retorna `scope.none` | Nenhuma linha liberada pela base |
| Filtro auxiliar | `account_scope` protegido aplica Account apos validar contexto | Nao substitui empresa/unidade/fila/propriedade/policy concreta |
| Controller | `Api::V1::Accounts::JrcServiceDesk::BaseController` | Herda autenticacao/contexto nativo; nenhuma rota/acao publica registrada |
| Verificacao | Gate local; `verify_authorized`; `verify_policy_scoped` para index | Nao modifica callbacks dos controllers existentes |
| Frontend | Apenas constante `FEATURE_FLAGS.JRC_SERVICE_DESK` | Nenhum componente, menu, store, cliente HTTP ou rota novo |

A checagem nao usa disponibilidade online/offline como autenticacao. `AccountUser#persisted?`
separa um vinculo existente de um objeto ainda nao persistido, mas nao reconsulta o banco:
controllers usam o vinculo resolvido pelo helper nativo; futuros jobs precisam reconstruir e
revalidar o contexto a cada execucao. Nao aceitar um hash enviado pelo browser, NICO ou webhook
como `user_context`. Tokens de bots sem AccountUser nao recebem acesso por esta base.

## Feature flag

- Nome backend: `jrc_service_desk`; constante Ruby: `JrcServiceDesk::FEATURE_FLAG`.
- Nome frontend: `FEATURE_FLAGS.JRC_SERVICE_DESK`.
- Default: `false`; sem habilitacao de Account, seeds, backfill ou chamada a `enable_features!` em producao.
- Coluna existente: `feature_flags_ext_1`; posicao persistida 9 (indice zero-based 8); mascara decimal 256.
- Coluna primaria: 63 flags, sem alteracao. Extensao: 8 anteriores + 1 nova = 9.
- Todos os 71 registros anteriores permanecem na mesma ordem, coluna, posicao e com os mesmos metadados.
- Nao foi definida classificacao premium/licenca para o novo modulo: essa decisao nao esta nos anexos.
- Efeito aditivo esperado: o registro nativo de features pode listar o novo nome no Super Admin e
  `all_features` passa a poder incluir `jrc_service_desk: false`. Nao afirmar igualdade byte a byte
  desse payload. Flags anteriores, rotas, menus operacionais, eventos e jobs nao mudam.
- Flag ligada, sozinha, nao abre dados: a base de policies continua negando e nao existe endpoint novo.

## Separacao do Cockpit

`app/javascript/dashboard/routes/dashboard/jrcService/routes.js` e os componentes
`JrcCockpit.vue`, `JrcEmailCenter.vue`, `JrcCallsCenter.vue` nao foram alterados.
O redirecionamento `jrc_service_center -> jrc_cockpit` e preservado.
Nenhum arquivo inteiro de pacote auxiliar foi copiado por cima do JRC.
O namespace de controllers usa `.../jrc_service_desk/`, alinhado ao namespace obrigatorio.
O prefixo HTTP `/service_desk` da auditoria pode ser mapeado explicitamente para esse modulo
no checkpoint de endpoints; nada foi registrado em `config/routes.rb` agora.

## Validacao e limites de evidencia

Testes nativos adicionados: contextos, policies, base abstrata, flag/bitsets, callbacks HTTP
em controller anonimo de teste e constante frontend. Os testes Rails usam APENAS o banco de
teste e factories nativas; nao representam permissoes ou dados novos de producao.
A fixture `spec/fixtures/jrc_service_desk/checkpoint1_feature_baseline.json` deriva integralmente
do ZIP central: permite comparar definicoes anteriores, bits e constantes frontend.

No ambiente completo de testes, validar:
- specs dos cinco arquivos Ruby novos e `spec/models/concerns/featurable_spec.rb`;
- o spec Vitest da flag e as suites existentes afetadas;
- carregamento/autoload no Ruby fixado pela base, sem editar o Gemfile para contornar a versao;
- que o controller anonimo de teste nega flag desligada e contexto de outra Account;
- que flag ligada nao contorna a exigencia de policy;
- que a configuracao nativa de defaults nao foi modificada para habilitar automaticamente o modulo.

A validacao externa desta execucao (manifesto, logs, diff e relatorio) distingue testes puros,
checagens estaticas e suites que nao puderam executar. Resultado pendente nunca equivale a OK.

## Fontes locais

- ZIP central: `config/features.yml`, `app/models/concerns/featurable.rb`, `app/models/account_user.rb`,
  `app/controllers/concerns/ensure_current_account_helper.rb`, `app/policies/application_policy.rb`,
  `app/controllers/api/v1/accounts/base_controller.rb`, `lib/current.rb`, `db/schema.rb` e extensoes Enterprise.
- Service Desk: `JRC_Service_Desk_Projeto_Completo_DEV.docx`, telas 9, 10, 17, 18, 21 e 22,
  entidades minimas, seguranca e criterios de aceite.
- Permissoes: `JRC_Conversas_Matriz_Perfis_e_Permissoes.docx`, regras obrigatorias, secao 4
  (Service Desk - operacao), secao 15 (Administracao / Super Admin) e regra final.
- Projetos: `JRC_Conversas_Modulo_Projetos_Projeto_Completo_DEV_v1.docx`, declaracao de escopo e
  principios arquiteturais. Apenas referencia da separacao; nada implementado em Projetos.

## Resultado vigente - CP1-R2

As cinco decisoes arquiteturais estao aprovadas e registradas, sem alteracao de codigo
executavel nesta rodada. O Checkpoint 2 nao foi iniciado. Tabelas, APIs operacionais, portal,
calendarios, concessoes de permissao, telas, fluxos e Projetos nao foram implementados.

**CHECKPOINT 1: NAO APROVADO.** Falta somente a evidencia de validacao nativa exigida nesta
etapa; SD-D01 a SD-D05 nao sao mais pendencias de arquitetura.

A tentativa de preparar runtimes isolados nao obteve Ruby 3.4.4/Node 24.13.0: os downloads
oficiais falharam. As consultas por curl a cache.ruby-lang.org, nodejs.org, rubygems.org e
registry.npmjs.org retornaram erro 6 (resolucao de host); o downloader da ferramenta tambem
falhou para os dois runtimes. Corepack falhou ao buscar pnpm 10.2.0. Nao foi encontrado cache
compativel nos caminhos locais inspecionados. Nenhum binario alternativo foi usado como nativo.

Disponivel: Ruby 3.3.8, Node 22.16.0, Bundler 2.5.22. Exigido pela base: Ruby 3.4.4,
Node 24.13.0, Bundler 2.5.16 e pnpm 10.2.0. Bundle check/install local frozen interromperam
por divergencia de Ruby. Rails/RSpec e pnpm nao ficaram disponiveis. PostgreSQL/Redis de teste
tambem nao estao preparados neste ambiente. Nao houve inicializacao de banco nem migrations.

Os logs CP1-R2 distinguem verificacoes estaticas/isoladas executadas das tentativas nativas
bloqueadas ANTES dos testes. Nao converter ausencia de execucao em teste aprovado ou reprovado.
Faltam: carregar Rails/ActiveRecord e namespaces; executar zeitwerk:check; executar os cinco
specs RSpec CP1 e Featurable existente (incluindo HTTP/flag desligada); executar Vitest da flag
e smoke/regressao aplicavel no ambiente correto. Nao editar requisitos/lockfiles para passar.

Verificacoes reexecutadas no CP1-R2: 61 verificacoes Ruby isoladas (classes reais com doubles
de dados, nao Rails/RSpec), 4 testes Node do modulo real de constantes e 30 verificacoes
estaticas contra a base e a entrega CP1-R1. Todas passaram. Sintaxe dos 10 arquivos Ruby CP1
e dos 2 arquivos JavaScript aprovada nos runtimes disponiveis. Esses resultados NAO satisfazem
a exigencia de executar os runtimes exatos e as suites nativas pendentes.

## Historico de validacao - CP1-R1 (resultado anterior)

O resultado a seguir e anterior a aprovacao das decisoes. Nao usar as pendencias historicas
como pendencias arquiteturais atuais: as cinco escolhas foram resolvidas no CP1-R2.

**CHECKPOINT 1: NAO APROVADO.** A base limitada foi criada e os bloqueios foram documentados.

Evidencias executadas: 43 testes Ruby isolados (56 assertions), 3 testes Node do modulo real de
constantes, 24 verificacoes estaticas contra o ZIP original, sintaxe de 10 arquivos Ruby e de
2 arquivos JavaScript, e `git diff --check`, todos aprovados nas verificacoes correspondentes.

Os testes isolados usam doubles de contratos de dados, nao Rails ou banco. Nao comprovam
carregamento ActiveRecord/Zeitwerk nem autenticacao/callbacks HTTP em execucao.
As tentativas de executar RSpec/Rails retornaram executaveis ausentes; pnpm tambem esta ausente.
Ruby disponivel: 3.3.8, requerido: 3.4.4. Node disponivel: 22.16.0, requerido: 24.13.0.
Nenhum requisito de runtime/lockfile foi alterado para contornar essas limitacoes.

Falta para aprovacao: resolver ou delimitar formalmente SD-D01 a SD-D05 e executar as validacoes
nativas de carregamento, RSpec/Featurable/HTTP e Vitest no ambiente correto, com banco de teste
isolado. Nao ha autorizacao para iniciar Checkpoint 2.
