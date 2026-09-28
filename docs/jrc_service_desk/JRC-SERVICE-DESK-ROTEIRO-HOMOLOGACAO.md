# JRC SERVICE DESK - ROTEIRO DE HOMOLOGACAO DOCKER/SERVIDOR

**CANDIDATO PARA HOMOLOGAÇÃO — VALIDAÇÃO NATIVA PENDENTE**

**PENDENTE — validação nativa em Docker/servidor**

Este documento e um roteiro A EXECUTAR. Nenhuma acao manual, boot, migration, requestHTTP, SQL, F5 ou avaliacao visual descrita aqui foi executada no ambiente nativo por esta entrega.

Candidato: `JRC-CONVERSAS-SERVICE-DESK-CANDIDATO-HOMOLOGACAO-20260928-R2.zip`. Conferir o SHA-256 no arquivo externo de checksums; evita hash circular dentro do proprio pacote. Base imediata: candidato CP6 `75bf3a187e5fd98430df3148664f136177a6bf58ee18140a4511f0a1cc94e3fe`; historico anterior CP5 preservado no relatorio de origem.

**Gate de inicio:** CP6-D01 APROVADA. Inicializacao humana implementada; designacao nominativa do funcionario e capacidades do cliente devem ser configuradas explicitamente no destino. Nenhum acesso e concedido no boot.

## FASE 1 - Infraestrutura e runtime

Usar uma copia isolada, volumes/bancos proprios e portas livres. Nao apontar o candidato para bancos ou containers de outro JRC. O nome do projeto Compose, sozinho, nao evita colisao de portas ou de volumes external/name. Inspecionar docker-compose.yaml e o arquivo local que sera realmente usado. O Compose incluido possui rails/sidekiq/vite/postgres/redis/mailhog, portas 3011,3047,55453,56401,1036,8037 e volumes com dados. Nenhuma alteracao automatica desses recursos foi feita. docker-compose.test.yaml NAO deve ser presumido como ambiente RSpec: seus argumentos/grupos precisam ser conferidos.

No Dockerfile, Node foi alinhado a .nvmrc e pnpm exige lockfile congelado; pull/build ainda nao foram testados. Verificar BUNDLE_WITHOUT vazio para testes. As configuracoes de projeto/ambiente abaixo sao PREENCHIDAS pelo responsavel apos revisar o destino, nao valores descobertos por este pacote.

```sh
# Na maquina Docker, antes de executar os comandos subsequentes:
export JRC_LAB_PROJECT="jrc-sd-cp6-lab"
export JRC_LAB_COMPOSE="/CAMINHO/ABSOLUTO/compose-lab-revisado.yaml"
export JRC_LAB_ENV="/CAMINHO/ABSOLUTO/ambiente-lab.env"
export JRC_LAB_DB="NOME_DO_BANCO_MANUAL_EXCLUSIVO"
export JRC_TEST_DB="NOME_DO_BANCO_RSPEC_DESCARTAVEL"
export JRC_DB_USER="USUARIO_DO_BANCO_LAB"
export JRC_EVIDENCIAS="/CAMINHO/SEGURO/evidencias-cp6"
# --env-file nao substitui sozinho env_file dos servicos; conferir ambos no Compose.
dc() { docker compose --project-name "$JRC_LAB_PROJECT" --env-file "$JRC_LAB_ENV" -f "$JRC_LAB_COMPOSE" "$@"; }
docker version
docker compose version
# Gerar config resolvida em arquivo RESTRITO; ela pode conter segredos. Nao anexar sem redigir.
dc config --services
dc ps
# Verificar hash usando o arquivo de checksums externo da entrega.
sha256sum JRC-CONVERSAS-SERVICE-DESK-CANDIDATO-HOMOLOGACAO-20260928-R2.zip
unzip -tq JRC-CONVERSAS-SERVICE-DESK-CANDIDATO-HOMOLOGACAO-20260928-R2.zip
# Construir imagens e iniciar SOMENTE infraestrutura apos revisar configuracao/backup:
dc build base
dc build rails vite
dc up -d postgres redis mailhog
# Runtimes no container/ferramenta de teste:
dc run --rm --no-deps --entrypoint sh rails -lc 'ruby -v; node -v; bundle -v; pnpm -v'
```

### INF-01

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | ZIP e checksum recebidos; nenhum servidor alterado. |
| AÇÃO | Comparar SHA-256 externo e CRC; conferir raiz extraida. |
| RESULTADO ESPERADO | Hash exato ao manifesto; CRC sem erro. Qualquer divergencia interrompe a preparacao. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### INF-02

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Manifesto Compose local revisado e portas/volumes isolados. |
| AÇÃO | Conferir todos os runtimes e imagem real. |
| RESULTADO ESPERADO | Ruby3.4.4, Node24.13.0, Bundler2.5.16, pnpm10.2.0; PostgreSQL compativel com as migrations e Redis separado. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### INF-03

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Dependencias somente pelos lockfiles do candidato. |
| AÇÃO | Instalar com bundle frozen e pnpm --frozen-lockfile; comparar hashes antes/depois. |
| RESULTADO ESPERADO | Nenhuma alteracao em Gemfile/lockfiles/package.json/.ruby-version/.nvmrc. Falha nao e corrigida mudando versao declarada. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

## FASE 2 - Backup

Antes de atualizar qualquer banco de laboratorio existente: confirmar HOST/PORT/DATABASE/usuario sem revelar senha; obter backup consistente e inventario de Active Storage/volumes. Registrar restauracao de verificacao em OUTRO banco vazio autorizado. Nao usar restore para sobrepor dados existentes; este roteiro nao executa reset/drop/truncate. Se o banco foi criado vazio para este ensaio, registrar essa condicao e nao inventar backup anterior.

```sh
# Somente depois de confirmar que estes nomes sao do laboratorio correto:
mkdir -p "$JRC_EVIDENCIAS"
dc exec -T postgres pg_dump -U "$JRC_DB_USER" -d "$JRC_LAB_DB" -Fc > "$JRC_EVIDENCIAS/antes-cp6.dump"
test -s "$JRC_EVIDENCIAS/antes-cp6.dump"
sha256sum "$JRC_EVIDENCIAS/antes-cp6.dump"
# Listar conteudo: nao restaura nem modifica banco.
dc exec -T postgres pg_restore --list < "$JRC_EVIDENCIAS/antes-cp6.dump" > "$JRC_EVIDENCIAS/backup-conteudo.txt"
```

### BKP-01

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Destino e permissao de backup confirmados. |
| AÇÃO | Gerar dump/inventario de arquivos; conferir tamanho e checksum. |
| RESULTADO ESPERADO | Backup legivel, consistente e acessivel ao responsavel, sem anexar credenciais. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### BKP-02

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Outro banco vazio autorizado para prova de recuperacao. |
| AÇÃO | Executar procedimento de restauracao revisado pelo responsavel; comparar contagens/referencias. |
| RESULTADO ESPERADO | Recuperacao demonstrada nesse banco separado; nenhuma base existente sobrescrita. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

## FASE 3 - Migrations

Conferir CP6_MIGRATIONS.md/JSON. CP6 nao cria migration: aplicar em ordem as tres acumuladas do Service Desk, sem reeditar as 204 anteriores. schema.rb continua anterior e deve ser gerado SOMENTE pelo Rails. O grupo de indices nativos usa CONCURRENTLY; verificar validade se houver interrupcao. Nunca remover indice ou dados automaticamente para fazer uma retentativa passar.

IMPORTANTE: config/database.yml usa POSTGRES_DATABASE inclusive em test. Apenas RAILS_ENV=test NAO garante banco separado. Conferir tambem DATABASE_URL e env_file: a conexao efetiva deve ser a autorizada. RSpec usa maintain_test_schema! e pode preparar schema; verifique o destino antes de iniciar qualquer suite.

```sh
# Depois do boot de infraestrutura e disponibilidade de dependencias (sem chamar o entrypoint normal):
dc run --rm --no-deps --entrypoint sh -e RAILS_ENV=test -e POSTGRES_DATABASE="$JRC_TEST_DB" rails -lc   "bundle exec rails runner 'puts ActiveRecord::Base.connection_db_config.configuration_hash.slice(:host, :port, :database).inspect'"
# Somente se a saida anterior for exatamente o banco RSpec exclusivo:
dc run --rm --no-deps --entrypoint sh -e RAILS_ENV=test -e POSTGRES_DATABASE="$JRC_TEST_DB" rails -lc 'bundle exec rails db:migrate:status'
dc run --rm --no-deps --entrypoint sh -e RAILS_ENV=test -e POSTGRES_DATABASE="$JRC_TEST_DB" rails -lc 'bundle exec rails db:migrate'
# Para a interface manual, conferir e migrar SEPARADAMENTE o banco do laboratorio.
# Guardar o diff de schema gerado; nao reutilizar JRC_TEST_DB como banco de uso manual.
```

### MIG-01

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Backup/preparacao e conexao efetiva aprovados. |
| AÇÃO | Listar migrations pendentes e aplicar pelos comandos Rails. |
| RESULTADO ESPERADO | Ordem:20260925190000,20260925190100,20260928120000; nenhuma migration CP6 inventada. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### MIG-02

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Migration aplicada no banco exclusivo. |
| AÇÃO | Inspecionar pg_constraint/pg_index/schema e comparar a matriz de declaracoes. |
| RESULTADO ESPERADO | 20 tabelas SD;69 indices declarados (4 auxiliares nativos);79FKs;30CHECKs;2colunas de ticket; nenhum indice invalido. Registrar diferencas reais. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### MIG-03

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Banco OUTRO descartavel reservado a rollback. |
| AÇÃO | Testar caminho vazio e recusa antes de apagar estrutura com registros. |
| RESULTADO ESPERADO | Rollback populado negado; rollback vazio coerente com dependencias. Nenhum dado apagado para satisfazer teste. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

## FASE 4 - Boot Rails, Sidekiq e Vite

Os comandos abaixo sao de laboratorio. Build nao foi executado aqui. O Compose revisado deve apontar somente aos bancos/Redis/mailhog de teste e possuir dependencias de development/test; desabilitar integracoes externas reais no ambiente. Verificar entrypoints antes de executa-los: eles podem instalar gems/preparar cache. Fazer inventario de processos/portas em vez de assumir que uma imagem antiga representa o candidato.

```sh
dc build base
dc build rails vite
# Somente apos revisar bancos, portas, volumes e env do laboratorio:
dc up -d postgres redis mailhog
dc up -d rails sidekiq vite
dc ps
dc logs --tail=150 rails sidekiq vite
# No destino de teste exclusivo:
dc exec -T -e RAILS_ENV=test -e POSTGRES_DATABASE="$JRC_TEST_DB" rails bundle exec rails zeitwerk:check
dc exec -T -e RAILS_ENV=test -e POSTGRES_DATABASE="$JRC_TEST_DB" rails bundle exec rails runner 'puts [Rails.version, ActiveRecord.version, JrcServiceDesk::Ticket.table_name].inspect'
```

### BOOT-01

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Banco/Redis corretos e deps frozen presentes. |
| AÇÃO | Subir Rails/Sidekiq/Vite; capturar logs sem segredos. |
| RESULTADO ESPERADO | Sem LoadError/Zeitwerk/erro SQL/SFC; runtime e codigo correspondem ao SHA do candidato. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### BOOT-02

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Conexao RSpec exclusiva conferida. |
| AÇÃO | Executar suites nativas listadas ao final deste roteiro. |
| RESULTADO ESPERADO | Guardar contagens/falhas/skips reais. Skip ou suite ausente nao e aprovacao. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

## FASE 5 - Feature flag

Nao ha ativacao automatica. Comecar com jrc_service_desk=false. Confirmar posicao9/mascara256 em feature_flags_ext_1 e as71flags anteriores. Habilitar manualmente APENAS a Account laboratorial escolhida, pelo mecanismo nativo autorizado. Nao habilitar contas em lote, nem atribuir unidades implicitamente.

### FLAG-01

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Usuario nativo valido; flag false. |
| AÇÃO | Abrir sidebar, URL profunda SD e cada grupo de API. |
| RESULTADO ESPERADO | Item ausente, rota negada, API nao opera; canais/Cockpit atuais preservados. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### FLAG-02

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Account de laboratorio e operador autorizado a alterar flag. |
| AÇÃO | Habilitar somente essa Account, sem conceder membership. |
| RESULTADO ESPERADO | Flag sozinha nao permite o modulo; sem membership continua negado. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### FLAG-03

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Sessao com dados SD e membership valido. |
| AÇÃO | Revogar flag em outra sessao; tentar API, trocar foco/aguardar revalidacao. |
| RESULTADO ESPERADO | API nega; frontend remove contexto na verificacao de foco/visibilidade/intervalo ate60s. Nao exigir notificacao push instantanea inexistente. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

## FASE 6 - Inicializacao humana de Account/Operadora/Unidade

Esta etapa substitui o bloqueio CP6-D01 anterior. No servidor, o responsavel identifica o
funcionario JRC que JA possui sessao SuperAdmin nativa autorizada. Configurar no ambiente do
Rails `JRC_SERVICE_DESK_INITIALIZER_USER_IDS` com IDs User exatos separados por virgula.
Nao usar email/dominio como prova, nao preencher IDs ficticios, nao promover agente a SuperAdmin
automaticamente. Lista ausente/invalida nega. Alteracao de env requer aplicar/reiniciar somente
os containers conforme o procedimento aprovado do laboratorio; nao muda flags ou grants.

Pela tela nativa da Account, preparar ANTES um usuario cliente confirmado e seu AccountUser
com papel autorizado (sem criar seu UnitMembership por console). Ligar a flag SD somente por
acao humana nativa da Fase5. Acessar o botao de inicializacao em Super Admin -> Account ou:
`/super_admin/accounts/ID_REAL/service-desk-initialization`.

Preencher nomes/codigos reais de operadora/unidade; selecionar o AccountUser cliente; informar
referencia de autorizacao; marcar confirmacao; enviar. A acao e transacional: operadora + unidade
+ primeiro grant + auditoria. Nao e possivel selecionar o ator ou outro SuperAdmin. A lista de
candidatos e limitada a50 por busca; refinar a busca quando necessario.

### EST-01

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Account SD vazia, funcionario designado, flag ligada e usuario cliente confirmado existente. |
| AÇÃO | Abrir formulario sem enviar e conferir tabelas read-only. |
| RESULTADO ESPERADO | GET nao cria operadora/unidade/grant; funcionario continua sem AccountUser/UnitMembership naquela Account. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | Preencher: ator, horario, hash do candidato, request sem token, resposta, IDs reais, consultas read-only, auditoria e F5. |

### EST-02

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Mesma preparacao; nomes e destinatario conferidos por humano. |
| AÇÃO | Enviar formulario, seguir GET recibo e F5; comparar dados e auditoria. |
| RESULTADO ESPERADO | Uma operadora, uma unidade e um grant do cliente; recibo do autor e tres eventos estruturais. Nenhum grant do funcionario, nenhum role ou flag alterado. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | Preencher: ator, horario, hash do candidato, request sem token, resposta, IDs reais, consultas read-only, auditoria e F5. |

### EST-03

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Formulario anterior concluido. |
| AÇÃO | Repetir POST com mesma chave/conteudo; depois tentar chave/conteudo diferentes. |
| RESULTADO ESPERADO | Mesma tentativa devolve recibo sem duplicar; tentativa nova em Account nao vazia e negada, sem mesclar/resetar dados. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | Preencher: ator, horario, hash do candidato, request sem token, resposta, IDs reais, consultas read-only, auditoria e F5. |

### EST-04

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Funcionario sem designacao, designacao revogada ou usuario normal administrador. |
| AÇÃO | Tentar GET/POST de inicializacao; depois repetir com flag falsa. |
| RESULTADO ESPERADO | Negar e manter banco inalterado. Remover designacao nao remove log; nao altera capacidades nativas de outras partes do sistema. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | Preencher: ator, horario, hash do candidato, request sem token, resposta, IDs reais, consultas read-only, auditoria e F5. |

### EST-05

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Sessao correta e Account vazia. |
| AÇÃO | Enviar AccountUser estrangeiro, ator ou SuperAdmin; remover CSRF/confirmacao/referencia. |
| RESULTADO ESPERADO | Falha segura sem estrutura parcial; resposta nao revela dados da outra Account. Auditoria de sucesso nao e fabricada. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | Preencher: ator, horario, hash do candidato, request sem token, resposta, IDs reais, consultas read-only, auditoria e F5. |

### EST-06

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Banco de teste exclusivo com duas conexoes. |
| AÇÃO | Submeter simultaneamente duas inicializacoes da mesma Account. |
| RESULTADO ESPERADO | Lock Account serializa: uma inicializacao; outra idempotente ou conflito. Registrar resultado real; teste nao foi executado nesta entrega. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | Preencher: ator, horario, hash do candidato, request sem token, resposta, IDs reais, consultas read-only, auditoria e F5. |

### EST-07

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Qualquer estrutura SD parcial/preexistente. |
| AÇÃO | Tentar inicializacao, sem remover os dados. |
| RESULTADO ESPERADO | Recusar mesclagem/reset automaticamente. Usar autoridade estrutural explicitamente delegada para a administracao cabivel. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | Preencher: ator, horario, hash do candidato, request sem token, resposta, IDs reais, consultas read-only, auditoria e F5. |

## FASE 7 - Usuarios, delegacao e UnitMembership

Primeiro grant nao inclui capacidades novas. Utilizar o editor NATIVO CustomRoles para atribuir,
explicitamente, structure_view e somente os manages necessarios ao AccountUser administrador
cliente. Prefixo de cada chave: jrc_service_desk_. O CustomRole substitui os defaults: incluir
capacidades operacionais separadamente somente quando autorizadas. A disponibilidade da
extensao/feature CustomRoles continua nativa; nao e habilitada pelo pacote.

A area `/app/accounts/:accountId/service-desk-structure` fica na sidebar somente apos contexto
backend afirmativo. Autoridade estrutural e Account-level e nao recebe tickets/KPIs/mensagens.
Gestao de grants: sem autoconcessao/reativacao propria; sem DELETE. Revogacao propria e permitida
por acao explicita. Nunca usar Team para substituir UnitMembership.

### USR-01

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Cliente administrador com capabilities estruturais explicitas, sem membership ativo. |
| AÇÃO | Abrir estrutura, consultar/criar unidade; tentar API de tickets e dashboard. |
| RESULTADO ESPERADO | Estrutura permitida; unidade nova sem grant automatico; operacao negada por falta de membership/capacidade operacional. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | Preencher: ator, horario, hash do candidato, request sem token, resposta, IDs reais, consultas read-only, auditoria e F5. |

### USR-02

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Usuario alvo e administrador estrutural diferentes. |
| AÇÃO | Criar/ativar/desativar UnitMembership; GET recibo e registro; F5. |
| RESULTADO ESPERADO | Escopo persiste com autor/motivo. Nenhum papel/capacidade alterado; operacao do alvo depende de seus demais gates. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | Preencher: ator, horario, hash do candidato, request sem token, resposta, IDs reais, consultas read-only, auditoria e F5. |

### USR-03

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Administrador com capacidade de gerenciar membership. |
| AÇÃO | Tentar conceder/reativar o proprio grant; depois revogar o proprio grant. |
| RESULTADO ESPERADO | Autoconcessao negada; revogacao explicita possivel; acesso operacional cai e nao e restaurado por administrar estrutura. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | Preencher: ator, horario, hash do candidato, request sem token, resposta, IDs reais, consultas read-only, auditoria e F5. |

### USR-04

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Duas Accounts e unidades distintas, IDs conhecidos. |
| AÇÃO | Enviar FK de operadora, unidade ou AccountUser estrangeiro; tentar receipt estrangeiro. |
| RESULTADO ESPERADO | Backend nega/falha sem escrita parcial; nenhum lookup ou recibo cruza Account. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | Preencher: ator, horario, hash do candidato, request sem token, resposta, IDs reais, consultas read-only, auditoria e F5. |

### USR-05

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Admin nativo sem CustomRole estrutural ou papel sem uma acao. |
| AÇÃO | Abrir deep link e chamar POST/PATCH diretamente. |
| RESULTADO ESPERADO | Sem concessao explicita: negar; admin sozinho e Team nao autorizam estruturar. Replays reavaliam capacidade. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | Preencher: ator, horario, hash do candidato, request sem token, resposta, IDs reais, consultas read-only, auditoria e F5. |

### USR-06

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Dados ja exibidos no navegador. |
| AÇÃO | Revogar capacidade/flag e trocar Account; atrasar resposta antiga. |
| RESULTADO ESPERADO | Proxima API nega; foco/visibilidade/timer revalidam e limpam. Resposta anterior nao repovoa a nova Account. Nao ha push instantaneo. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | Preencher: ator, horario, hash do candidato, request sem token, resposta, IDs reais, consultas read-only, auditoria e F5. |

### USR-07

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Registro estrutural lido por duas sessoes. |
| AÇÃO | Editar com revisao antiga; simular erro no GET apos escrita confirmada pelo POST. |
| RESULTADO ESPERADO | Conflito sem sobrescrita silenciosa; erro de releitura nao e sucesso falso. Recuperar a mesma chave antes de nova intencao. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | Preencher: ator, horario, hash do candidato, request sem token, resposta, IDs reais, consultas read-only, auditoria e F5. |

## FASE 8 - Permissoes

Conferir CP6_PERMISSOES.md:37capacidades SD:33anteriores +4estruturais explicitas. Defaults operacionais preservados:23agente/33admin; novas4 sem defaults. Operacao exige membership; autoridade estrutural explicitamente delegada e separada. Roles existentes sem grantsSD negam; custom role substitui defaults. Editor nativo CustomRoles depende da disponibilidade da extensao/feature original, sem ativacao automatica. Nao excluir papel para revogar: a exclusao nativa pode restaurar o perfil-base; usar revogacao de escopo/capacidade explicitamente autorizada.

### PERM-01

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Ator com membership mas customrole sem uma capacidade especifica. |
| AÇÃO | Tentar criar, editar, mudar prioridade, atribuir, transferir, publicar politica por API direta. |
| RESULTADO ESPERADO | Cada capacidade independente; PATCH misto nao grava parcialmente; IDs conhecidos nao concedem acesso. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### PERM-02

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Gestor de um catalogo, com unitgrant e capacidade correspondente. |
| AÇÃO | Criar, reler, editar, ativar/desativar fila/categoria/prioridade/status/servico. |
| RESULTADO ESPERADO | Recibo nativo associado a Unit; Account/autor/unidade/antes/depois corretos; GET e F5 preservam; sem DELETE. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### PERM-03

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Duas unidades; auditor de Account sem membership da segunda. |
| AÇÃO | Consultar endpoint geral nativo de auditoria e recibo SD da outra unidade. |
| RESULTADO ESPERADO | Audits SD de configuracao nao aparecem por Account.associated_audits; recibo cruzado negado. SQL privilegiado nao e modelo de usuario final. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

## FASE 9 - Politica de ciclo e SLA

Usar editor JSON avancado, nao editor visual. Cada valor de negocio deve ser configurado explicitamente. Publicar versao de unidade ou servico+unidade; especifica prevalece, especifica desabilitada nega fallback. Sem politica aplicavel, negar. Chamados ja vinculados mantem versao. Status com fase referenciada nao pode mudar familia.

Para ensaio SEM SLA, not_applicable deve ser escolha explicita e registrada, nao fallback. Para ensaio COM SLA, o snapshot v1 com timezone IANA, semana, feriados, excecoes e metas deve estar presente por origem autorizada. O gravador de snapshot continua interno, sem UI/API de captura: se faltar esse dado, registrar dependencia funcional; nao substituir por calendario ficticio. As factories de ciclo/canonicalcalendar no RSpec exercitam o algoritmo no banco de teste, nao certificam contratos externos.

### CIC-01

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Status configurados, gestor com lifecycle_policies_manage e unitgrant. |
| AÇÃO | Publicar politica e reler ID/versao/digest; publicar nova versao. |
| RESULTADO ESPERADO | Primeira versao imutavel; tickets antigos preservam referencia. Policy estrangeira negada. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### CIC-02

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Politica explicita para pause/resume/resolve/close/cancel/reopen. |
| AÇÃO | Testar cada transicao permitida e cada precondicao ausente. |
| RESULTADO ESPERADO | Motivo explicito; waiting nao pausa automaticamente; evidencia/notas/fields verificadas; nenhuma escrita parcial. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### CIC-03

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Snapshot v1 autorizado com timezone real e clocktargets; executor com sla_view. |
| AÇÃO | Testar feriado/excecao/DST/virada do dia, pausas seletivas, reopen continue/new. |
| RESULTADO ESPERADO | Calculo do backend com versoes e ciclos preservados; ambiguidades/dependencia bloqueiam. Nota interna nao realiza primeira resposta. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### CIC-04

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Snapshot real compativel ausente ou calendario fora do contrato v1. |
| AÇÃO | Tentar operacao dependente de SLA calculado. |
| RESULTADO ESPERADO | Dependencia explicita; nenhuma suposicao24x7 ou first_response ficticia. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE FUNCIONAL |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

## FASE 10 - Fluxos funcionais e todos os botoes

Usar CP6_BOTOES_FLUXOS.md/JSON e CP6_FLUXOS_CRITICOS.md como checklist. Cada linha possui origem do componente e camada esperada. Registrar o clique, request (sem token), resposta, consulta do registro no banco, mudanca na tela, F5 e KPI. Elemento desabilitado por funcionalidade futura nao deve produzir falso sucesso. Um botao local de filtro/aba nao precisa gravar banco; marcar essa coluna N/A. Os testes abaixo sao a instancia manual dos22fluxos criticos; executar tambem todas as linhas dinamicas/admin na matriz de botoes.

### FLX-01

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Flag, contexto, unitgrant, capacidade, dados e politica exigidos pela linha da matriz presentes. |
| AÇÃO | criar chamado: Novo / salvar |
| RESULTADO ESPERADO | UI -> request -> API/Pundit -> service -> commit -> resposta -> GET independente -> UI -> F5. Conferir registros/auditoria/KPI conforme CP6_FLUXOS_CRITICOS, sem estado local usado como persistencia. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### FLX-02

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Flag, contexto, unitgrant, capacidade, dados e politica exigidos pela linha da matriz presentes. |
| AÇÃO | editar chamado: Editar / salvar |
| RESULTADO ESPERADO | UI -> request -> API/Pundit -> service -> commit -> resposta -> GET independente -> UI -> F5. Conferir registros/auditoria/KPI conforme CP6_FLUXOS_CRITICOS, sem estado local usado como persistencia. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### FLX-03

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Flag, contexto, unitgrant, capacidade, dados e politica exigidos pela linha da matriz presentes. |
| AÇÃO | atribuir: Atribuir / salvar |
| RESULTADO ESPERADO | UI -> request -> API/Pundit -> service -> commit -> resposta -> GET independente -> UI -> F5. Conferir registros/auditoria/KPI conforme CP6_FLUXOS_CRITICOS, sem estado local usado como persistencia. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### FLX-04

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Flag, contexto, unitgrant, capacidade, dados e politica exigidos pela linha da matriz presentes. |
| AÇÃO | transferir: Transferir / salvar |
| RESULTADO ESPERADO | UI -> request -> API/Pundit -> service -> commit -> resposta -> GET independente -> UI -> F5. Conferir registros/auditoria/KPI conforme CP6_FLUXOS_CRITICOS, sem estado local usado como persistencia. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### FLX-05

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Flag, contexto, unitgrant, capacidade, dados e politica exigidos pela linha da matriz presentes. |
| AÇÃO | alterar prioridade: Prioridade / salvar |
| RESULTADO ESPERADO | UI -> request -> API/Pundit -> service -> commit -> resposta -> GET independente -> UI -> F5. Conferir registros/auditoria/KPI conforme CP6_FLUXOS_CRITICOS, sem estado local usado como persistencia. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### FLX-06

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Flag, contexto, unitgrant, capacidade, dados e politica exigidos pela linha da matriz presentes. |
| AÇÃO | alterar status trabalho: Status / salvar |
| RESULTADO ESPERADO | UI -> request -> API/Pundit -> service -> commit -> resposta -> GET independente -> UI -> F5. Conferir registros/auditoria/KPI conforme CP6_FLUXOS_CRITICOS, sem estado local usado como persistencia. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### FLX-07

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Flag, contexto, unitgrant, capacidade, dados e politica exigidos pela linha da matriz presentes. |
| AÇÃO | adicionar nota: Adicionar nota |
| RESULTADO ESPERADO | UI -> request -> API/Pundit -> service -> commit -> resposta -> GET independente -> UI -> F5. Conferir registros/auditoria/KPI conforme CP6_FLUXOS_CRITICOS, sem estado local usado como persistencia. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### FLX-08

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Flag, contexto, unitgrant, capacidade, dados e politica exigidos pela linha da matriz presentes. |
| AÇÃO | consultar historico: Historico / paginar |
| RESULTADO ESPERADO | UI -> request -> API/Pundit -> service -> commit -> resposta -> GET independente -> UI -> F5. Conferir registros/auditoria/KPI conforme CP6_FLUXOS_CRITICOS, sem estado local usado como persistencia. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### FLX-09

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Flag, contexto, unitgrant, capacidade, dados e politica exigidos pela linha da matriz presentes. |
| AÇÃO | vincular conversa: Relacionar / vincular |
| RESULTADO ESPERADO | UI -> request -> API/Pundit -> service -> commit -> resposta -> GET independente -> UI -> F5. Conferir registros/auditoria/KPI conforme CP6_FLUXOS_CRITICOS, sem estado local usado como persistencia. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### FLX-10

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Flag, contexto, unitgrant, capacidade, dados e politica exigidos pela linha da matriz presentes. |
| AÇÃO | navegar conversa: Abrir conversa |
| RESULTADO ESPERADO | UI -> request -> API/Pundit -> service -> commit -> resposta -> GET independente -> UI -> F5. Conferir registros/auditoria/KPI conforme CP6_FLUXOS_CRITICOS, sem estado local usado como persistencia. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### FLX-11

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Flag, contexto, unitgrant, capacidade, dados e politica exigidos pela linha da matriz presentes. |
| AÇÃO | pausar: Pausar / aplicar |
| RESULTADO ESPERADO | UI -> request -> API/Pundit -> service -> commit -> resposta -> GET independente -> UI -> F5. Conferir registros/auditoria/KPI conforme CP6_FLUXOS_CRITICOS, sem estado local usado como persistencia. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### FLX-12

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Flag, contexto, unitgrant, capacidade, dados e politica exigidos pela linha da matriz presentes. |
| AÇÃO | retomar: Retomar / aplicar |
| RESULTADO ESPERADO | UI -> request -> API/Pundit -> service -> commit -> resposta -> GET independente -> UI -> F5. Conferir registros/auditoria/KPI conforme CP6_FLUXOS_CRITICOS, sem estado local usado como persistencia. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### FLX-13

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Flag, contexto, unitgrant, capacidade, dados e politica exigidos pela linha da matriz presentes. |
| AÇÃO | resolver: Resolver / aplicar |
| RESULTADO ESPERADO | UI -> request -> API/Pundit -> service -> commit -> resposta -> GET independente -> UI -> F5. Conferir registros/auditoria/KPI conforme CP6_FLUXOS_CRITICOS, sem estado local usado como persistencia. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### FLX-14

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Flag, contexto, unitgrant, capacidade, dados e politica exigidos pela linha da matriz presentes. |
| AÇÃO | encerrar: Encerrar / aplicar |
| RESULTADO ESPERADO | UI -> request -> API/Pundit -> service -> commit -> resposta -> GET independente -> UI -> F5. Conferir registros/auditoria/KPI conforme CP6_FLUXOS_CRITICOS, sem estado local usado como persistencia. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### FLX-15

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Flag, contexto, unitgrant, capacidade, dados e politica exigidos pela linha da matriz presentes. |
| AÇÃO | cancelar: Cancelar / aplicar |
| RESULTADO ESPERADO | UI -> request -> API/Pundit -> service -> commit -> resposta -> GET independente -> UI -> F5. Conferir registros/auditoria/KPI conforme CP6_FLUXOS_CRITICOS, sem estado local usado como persistencia. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### FLX-16

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Flag, contexto, unitgrant, capacidade, dados e politica exigidos pela linha da matriz presentes. |
| AÇÃO | reabrir: Reabrir / aplicar |
| RESULTADO ESPERADO | UI -> request -> API/Pundit -> service -> commit -> resposta -> GET independente -> UI -> F5. Conferir registros/auditoria/KPI conforme CP6_FLUXOS_CRITICOS, sem estado local usado como persistencia. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### FLX-17

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Flag, contexto, unitgrant, capacidade, dados e politica exigidos pela linha da matriz presentes. |
| AÇÃO | publicar politica: Publicar versao / habilitar |
| RESULTADO ESPERADO | UI -> request -> API/Pundit -> service -> commit -> resposta -> GET independente -> UI -> F5. Conferir registros/auditoria/KPI conforme CP6_FLUXOS_CRITICOS, sem estado local usado como persistencia. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### FLX-18

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Flag, contexto, unitgrant, capacidade, dados e politica exigidos pela linha da matriz presentes. |
| AÇÃO | visualizar SLA: SLA / atualizar |
| RESULTADO ESPERADO | UI -> request -> API/Pundit -> service -> commit -> resposta -> GET independente -> UI -> F5. Conferir registros/auditoria/KPI conforme CP6_FLUXOS_CRITICOS, sem estado local usado como persistencia. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### FLX-19

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Flag, contexto, unitgrant, capacidade, dados e politica exigidos pela linha da matriz presentes. |
| AÇÃO | filtros: Aplicar / limpar / ordenar / pesquisa |
| RESULTADO ESPERADO | UI -> request -> API/Pundit -> service -> commit -> resposta -> GET independente -> UI -> F5. Conferir registros/auditoria/KPI conforme CP6_FLUXOS_CRITICOS, sem estado local usado como persistencia. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### FLX-20

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Flag, contexto, unitgrant, capacidade, dados e politica exigidos pela linha da matriz presentes. |
| AÇÃO | paginacao: Anterior / proximo / pagina |
| RESULTADO ESPERADO | UI -> request -> API/Pundit -> service -> commit -> resposta -> GET independente -> UI -> F5. Conferir registros/auditoria/KPI conforme CP6_FLUXOS_CRITICOS, sem estado local usado como persistencia. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### FLX-21

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Flag, contexto, unitgrant, capacidade, dados e politica exigidos pela linha da matriz presentes. |
| AÇÃO | Minha Fila: Minha Fila / filtros |
| RESULTADO ESPERADO | UI -> request -> API/Pundit -> service -> commit -> resposta -> GET independente -> UI -> F5. Conferir registros/auditoria/KPI conforme CP6_FLUXOS_CRITICOS, sem estado local usado como persistencia. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### FLX-22

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Flag, contexto, unitgrant, capacidade, dados e politica exigidos pela linha da matriz presentes. |
| AÇÃO | dashboard/KPIs: Atualizar / detalhar status |
| RESULTADO ESPERADO | UI -> request -> API/Pundit -> service -> commit -> resposta -> GET independente -> UI -> F5. Conferir registros/auditoria/KPI conforme CP6_FLUXOS_CRITICOS, sem estado local usado como persistencia. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### ADM-01

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Gestor, unidade e5catalogos autorizados. |
| AÇÃO | Para cada fila/categoria/prioridade/status/servico: listar ativos/inativos; criar; editar; desativar; reativar; pesquisar; paginar; F5. |
| RESULTADO ESPERADO | Somente campos allowlist; unidade imutavel; codigo imutavel depois de criar; recibo+GET; nenhuma exclusao fisica. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### ADM-02

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Duas sessoes editam a mesma revisao. |
| AÇÃO | Salvar primeiro; tentar salvar segundo com revisao antiga; repetir mesma chave/payload; testar chave/payload diferente. |
| RESULTADO ESPERADO | Conflito real, sem sobrescrita silenciosa. Mesmo intento e chave retornam a operacao original; payload conflitante e rejeitado. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### ADM-03

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Status usado em ticket ou politica publicada sem ticket. |
| AÇÃO | Tentar editar sua fase; renomear sem editarfase; desativar politica existente com refs inativas. |
| RESULTADO ESPERADO | A fase fica protegida. Nome e atividade respeitam as validacoes. Desabilitar uma politica explicitamente preserva a definicao historica, sem reinterpretar eventos. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

## FASE 11 - Dashboard e KPIs

O dashboard usa TicketQuery e TicketPolicy::Scope, nao tamanho da pagina. Conferir CP6_KPIS.md/JSON. Criar dados CONTROLADOS em banco de teste:27tickets,8no statusAberto(open),12no statusEmAndamento(open),7no statusResolvido(resolved). Assim o agrupamento de familias e open20/resolved7/ativos20. Resolver um Aberto resulta7/12/8 por status; open19/resolved8/ativos19; total27. Nao confundir o nome configurado EmAndamento com uma sexta familia. Campos/distribuicoes de SLA/satisfacao sem fontes permanecem indisponiveis.

### KPI-01

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Dataset descrito, escopos e dados conhecidos; politica de resolucao configurada. |
| AÇÃO | Comparar SQL, GET /dashboard e cards. Resolver um chamado, reconsultar e pressionar F5. |
| RESULTADO ESPERADO | Por status: 27 = 8 + 12 + 7 passa a 27 = 7 + 12 + 8. Por familia: Total = open + waiting + resolved + closed + cancelled. Ativos = open + waiting. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### KPI-02

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Dois usuarios possuem unidades/visibilidade diferentes. |
| AÇÃO | Aplicar os mesmos filtros com cada usuario. Variar unidade, status, prioridade, fila, responsavel, Minha Fila e pagina. |
| RESULTADO ESPERADO | Valores diferentes podem ser corretos. Cada valor deve coincidir com a listagem autorizada e o total nao deve depender da pagina. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### KPI-03

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Consulta vazia real e erro deAPI reproduzivel. |
| AÇÃO | Aplicar filtro sem resultados e depois simular falha da API ou revogacao. |
| RESULTADO ESPERADO | Consulta bem-sucedida vazia pode retornar zero. Falha mostra erro ou negativa, nunca zero confirmado. Nao ha incremento local de contador. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

## FASE 12 - Seguranca

Executar variantes positivas e negativas por API direta, nao apenas ocultacao de botoes. Nao anexar tokens/senhas/dados de cliente aos logs. Alteracoes de fixture para ensaios de concorrencia pertencem exclusivamente ao banco descartavel autorizado.

### SEC-01

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Banco e atores de teste autorizados; captura de evidencias preparada. |
| AÇÃO | Substituir Account, unidade, operadora, responsavel, contato, empresa, conversa, politica e evidencia por IDs estrangeiros. |
| RESULTADO ESPERADO | Negativa segura 403/404/422 conforme contrato, sem dados de outro escopo e sem mutacao parcial. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### SEC-02

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Banco e atores de teste autorizados; ferramentas de captura prontas. |
| AÇÃO | Tentar acesso como administrador sem membership, membro de Team sem membership, usuario com vinculo mas sem capacidade e usuario com capacidade sem vinculo. |
| RESULTADO ESPERADO | Negar em todos os casos sem a intersecao obrigatoria. Nao acrescentar vinculo apenas para fazer um teste passar. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### SEC-03

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Banco e atores de teste autorizados; ferramentas de captura prontas. |
| AÇÃO | Revogar papel, capacidade, membership ou flag antes de leitura, escrita e repeticao idempotente. |
| RESULTADO ESPERADO | Nova operacao negada. A repeticao nao restaura privilegios. O frontend limpa o contexto depois da negativa ou revalidacao. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### SEC-04

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Banco e atores de teste autorizados; ferramentas de captura prontas. |
| AÇÃO | Trocar Account enquanto uma requisicao estiver lenta; entregar a resposta antiga depois da troca. |
| RESULTADO ESPERADO | Dados antigos nao repovoam o novo contexto. Rascunhos sao descartados e deep links reautorizados. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### SEC-05

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Banco e atores de teste autorizados; ferramentas de captura prontas. |
| AÇÃO | Tentar consultar notas, solucao, evidencias e campos de SLA somente com history_view; consultar recibo de outro autor ou unidade. |
| RESULTADO ESPERADO | Campos protegidos omitidos; requisitos privados de transicao exigem notes_view. Historico original permanece no banco. Recibo estrangeiro negado. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### SEC-06

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Banco e atores de teste autorizados; ferramentas de captura prontas. |
| AÇÃO | Executar duas mutacoes concorrentes com a mesma chave e depois uma atualizacao com revisao obsoleta. |
| RESULTADO ESPERADO | Uma intencao sem auditoria duplicada. Conflitos rejeitados. Registrar qualquer deadlock ou comportamento nao previsto na suite real. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

## FASE 13 - Regressao do JRC

A comparacao byte a byte e os testes isolados nao comprovam regressao operacional. Exercitar os modulos preexistentes antes e depois em ambiente comparavel. As foreign keys do Service Desk podem restringir exclusao ou merge nativo; nao remover historico para contornar erros. Projetos permanece fora do candidato.

### REG-01

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Baseline e candidato em laboratorios isolados, com os mesmos dados controlados. |
| AÇÃO | Exercitar os fluxos ja existentes de Conversas e canais e registrar comparacao. |
| RESULTADO ESPERADO | Nenhuma mudanca indevida fora do escopo; itens, rotas e permissoes anteriores preservados. Registrar qualquer erro observado. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### REG-02

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Baseline e candidato em laboratorios isolados, com os mesmos dados controlados. |
| AÇÃO | Exercitar os fluxos ja existentes de Cockpit/jrcService e registrar comparacao. |
| RESULTADO ESPERADO | Nenhuma mudanca indevida fora do escopo; itens, rotas e permissoes anteriores preservados. Registrar qualquer erro observado. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### REG-03

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Baseline e candidato em laboratorios isolados, com os mesmos dados controlados. |
| AÇÃO | Exercitar os fluxos ja existentes de CRM e registrar comparacao. |
| RESULTADO ESPERADO | Nenhuma mudanca indevida fora do escopo; itens, rotas e permissoes anteriores preservados. Registrar qualquer erro observado. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### REG-04

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Baseline e candidato em laboratorios isolados, com os mesmos dados controlados. |
| AÇÃO | Exercitar os fluxos ja existentes de Campanhas e registrar comparacao. |
| RESULTADO ESPERADO | Nenhuma mudanca indevida fora do escopo; itens, rotas e permissoes anteriores preservados. Registrar qualquer erro observado. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### REG-05

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Baseline e candidato em laboratorios isolados, com os mesmos dados controlados. |
| AÇÃO | Exercitar os fluxos ja existentes de NICO e registrar comparacao. |
| RESULTADO ESPERADO | Nenhuma mudanca indevida fora do escopo; itens, rotas e permissoes anteriores preservados. Registrar qualquer erro observado. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### REG-06

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Baseline e candidato em laboratorios isolados, com os mesmos dados controlados. |
| AÇÃO | Exercitar os fluxos ja existentes de Calling e registrar comparacao. |
| RESULTADO ESPERADO | Nenhuma mudanca indevida fora do escopo; itens, rotas e permissoes anteriores preservados. Registrar qualquer erro observado. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### REG-07

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Baseline e candidato em laboratorios isolados, com os mesmos dados controlados. |
| AÇÃO | Exercitar os fluxos ja existentes de Email Center e registrar comparacao. |
| RESULTADO ESPERADO | Nenhuma mudanca indevida fora do escopo; itens, rotas e permissoes anteriores preservados. Registrar qualquer erro observado. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### REG-08

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Baseline e candidato em laboratorios isolados, com os mesmos dados controlados. |
| AÇÃO | Exercitar os fluxos ja existentes de Calls Center e registrar comparacao. |
| RESULTADO ESPERADO | Nenhuma mudanca indevida fora do escopo; itens, rotas e permissoes anteriores preservados. Registrar qualquer erro observado. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### REG-09

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Baseline e candidato em laboratorios isolados, com os mesmos dados controlados. |
| AÇÃO | Exercitar os fluxos ja existentes de Contatos e Company e registrar comparacao. |
| RESULTADO ESPERADO | Nenhuma mudanca indevida fora do escopo; itens, rotas e permissoes anteriores preservados. Registrar qualquer erro observado. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### REG-10

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Baseline e candidato em laboratorios isolados, com os mesmos dados controlados. |
| AÇÃO | Exercitar os fluxos ja existentes de Autenticacao e CustomRoles e registrar comparacao. |
| RESULTADO ESPERADO | Nenhuma mudanca indevida fora do escopo; itens, rotas e permissoes anteriores preservados. Registrar qualquer erro observado. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### REG-11

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Dados de teste relacionados pelas foreign keys do Service Desk. |
| AÇÃO | Verificar exclusao, merge e retencao nativos sem apagar dados para fazer o teste passar. |
| RESULTADO ESPERADO | Restricoes de integridade explicitas, sem historico orfao nem vazamento na auditoria geral da Account. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

## FASE 14 - Refresh e persistencia

Para cada escrita, nao bastam notificacao visual ou estado em memoria. Capturar o ID real, fazer um GET independente e recarregar com F5. Em caso de timeout depois do commit, conferir recibo e listagem antes de enviar uma nova chave. Os cadastros recuperam a mesma tentativa/chave enquanto a pagina permanece aberta. F5 perde essa chave em memoria: nao presumir deduplicacao universal entre chaves diferentes.

### F5-01

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Escritas de chamados, cadastros e ciclo ja testadas. |
| AÇÃO | Reabrir em nova guia ou sessao autorizada, consultar pelo ID, pressionar F5 e conferir banco/indicadores. |
| RESULTADO ESPERADO | O mesmo estado e confirmado pelo backend. Nenhum localStorage e tratado como fonte persistente. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### F5-02

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Ferramenta preparada para interromper GET de confirmacao depois do commit. |
| AÇÃO | Bloquear a releitura apos POST/PATCH e repetir a mesma chave/intencao antes de F5. |
| RESULTADO ESPERADO | Exibir confirmacao pendente, nao sucesso falso. Nao afirmar que a escrita falhou quando ela pode existir. O recibo deve permitir recuperar a confirmacao. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### F5-03

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Operador pode perder visibilidade ao atribuir outro responsavel. |
| AÇÃO | Conferir o GET posterior com o ator original e com o destinatario legitimamente autorizado. |
| RESULTADO ESPERADO | Nao ampliar acesso para confirmar. A escrita pode existir com releitura negada ao ator original; a interface deve explicar essa limitacao. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

## FASE 15 - Evidencias e resultado

Preencher todas as linhas executadas e anexar evidencias sem segredos. Linhas sem alguma camada implementada continuam PENDENTE FUNCIONAL. Linhas que exigem execucao ainda nao realizada continuam PENDENTE DE EXECUCAO NATIVA. PRONTO PARA HOMOLOGACAO descreve preparacao para teste, nao resultado nativo. Nao iniciar outro checkpoint automaticamente depois desta avaliacao.

### EVD-01

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Todos os resultados e artefatos reunidos. |
| AÇÃO | Registrar SHA, ambiente, comandos, datas, atores, fixtures, requests, respostas, SQL, capturas e diffs gerados. |
| RESULTADO ESPERADO | Todo resultado obtido deve ter evidencia correspondente. Ausencia de erro em inspecoes nao prova um fluxo completo. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

### EVD-02

| CAMPO | REGISTRO |
|---|---|
| PRE-CONDIÇÃO | Pendencias e falhas reais revisadas pelo responsavel. |
| AÇÃO | Registrar CP6-D01 aprovada, resultados da inicializacao manual/delegacao, dependencias de snapshot/SLA, funcionalidades futuras e falhas reais de execucao. |
| RESULTADO ESPERADO | Manter a classificacao apropriada do candidato. A proxima acao depende da avaliacao humana, nao de avanco automatico. |
| RESULTADO OBTIDO | NAO EXECUTADO. Preencher no ambiente de teste. |
| STATUS | PENDENTE DE EXECUÇÃO NATIVA |
| EVIDÊNCIA | PREENCHER: horario, operador, hash do candidato, request/status, captura, log redigido e consulta de confirmacao. |

## Suites nativas a executar apos os gates

Confirmar banco test descartavel ANTES destes comandos. Nao usar a base de testes manuais, pois suites podem manipular suas fixtures.

```sh
# Dentro do container de testes com RAILS_ENV=test, DB/Redis confirmados e dependencias corretas:
bundle exec rails zeitwerk:check
bundle exec rspec spec/requests/api/v1/accounts/jrc_service_desk spec/models/jrc_service_desk spec/policies/jrc_service_desk spec/services/jrc_service_desk spec/serializers/jrc_service_desk spec/migrations/jrc_service_desk_core_spec.rb spec/controllers/api/v1/accounts/jrc_service_desk/base_controller_spec.rb spec/models/concerns/jrc_service_desk_feature_spec.rb spec/models/concerns/featurable_spec.rb
pnpm exec vitest run app/javascript/dashboard/routes/dashboard/serviceDesk/__tests__ app/javascript/dashboard/__tests__/serviceDeskFeatureFlag.spec.js
pnpm exec eslint app/javascript/dashboard/routes/dashboard/serviceDesk app/javascript/dashboard/api/serviceDeskConfiguration.js app/javascript/dashboard/api/serviceDeskConfigurationClient.js app/javascript/dashboard/composables/useServiceDeskNavigation.js
pnpm exec vite build
```

Executar tambem as suites nativas de CustomRole/AccountUser audit/Sidebar/formulario de papeis no ambiente com extensao aplicavel. Skip por extensao ausente NAO aprova essa integracao.

**Concorrencia opt-in:** `cp4_concurrency_spec.rb`, `lifecycle_concurrency_spec.rb`, `configuration_concurrency_spec.rb` requerem `JRC_SD_CONCURRENCY=1`, conexoes paralelas e fixtures commitadas. Executar ISOLADAMENTE num OUTRO banco descartavel de testes, depois de conferir todas as conexoes. Sem opt-in, skip continua pendente. Este roteiro nao apaga nem descarta bancos automaticamente.

## Registro reutilizavel para cada linha da matriz de botoes

| CAMPO | PREENCHER NO ENSAIO |
|---|---|
| ID da linha/tela/botao | |
| PRE-CONDICAO | Account, unidade, ator, membership, capacidades, politica, dados e versoes |
| ACAO | Clique real e passos |
| REQUEST/RESPOSTA | Metodo/caminho/status/corpo redigido; sem tokens |
| BANCO/AUDITORIA | IDs, consulta independente, timestamps, autor, antes/depois e versao |
| UI/RELEITURA/F5 | Capturas antes/depois e request de releitura |
| KPI | Query/valores antes/depois ou N/A fundamentado |
| RESULTADO ESPERADO | Copiar da matriz especifica |
| RESULTADO OBTIDO | NAO EXECUTADO - substituir somente apos executar |
| STATUS | PENDENTE DE EXECUCAO NATIVA; usar PENDENTE FUNCIONAL se falta camada |
| EVIDENCIA | Arquivo/log/horario/hash do candidato/responsavel |

Nenhum teste ausente pode ser registrado como sucesso. Projetos e outros checkpoints permanecem fora desta entrega.
