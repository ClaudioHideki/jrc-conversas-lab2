# Candidata consolidada de histórico WhatsApp — 12/11/2026

## Fechamento dos gates de consolidação

A CI de `c307e774` comprovou a suíte Rails de conexões, mas o build completo excedeu o heap padrão de 4 GiB. A guarda existente agora calcula 4096–6144 MiB a partir da RAM livre observada, conservando 1 GiB para alocações nativas/runner, o piso inicial de 5 GiB e a interrupção por reserva física. Seis regressões cobrem limites, autorização de SHA/branch e recusa no Windows; não houve alteração de recursos do servidor.

A CI nativa também detectou divergência entre migrations e schema: as migrations existentes de retry e exportação de relatório estavam presentes, mas `whatsapp_retry_attempts`, `whatsapp_retry_receipts` e `jrc_service_desk_report_exports` faltavam no schema consolidado. Foram acrescentadas somente suas definições, índices e FKs, sem editar migrations já publicadas nem reduzir a versão do schema. A guarda de runtime admite o hash exato dessa reconciliação e continua recusando mudanças não revistas.

O recibo de upgrade passa a exigir 38 versões: as 36 já admitidas mais as duas migrations de histórico desta branch, verificadas por hash em `history_forward_migrations_20261112.json`. A lista histórica de 27 migrations permanece intacta. O terceiro caminho do gate agora carrega explicitamente o `db/schema.rb` versionado, e não o schema temporário gerado pelo primeiro caminho; a comparação de catálogos de instalação nova, upgrade populado e carga de schema continua obrigatória. Apenas metadados de schema são produzidos em bases descartáveis; nenhuma rotina de backup de dados é executada.

Os 25 testes Python dos contratos/guardas passaram localmente. A carga corrigida foi executada em um PostgreSQL adicional, efêmero, sem volumes ou portas do host; não modificou o banco usado pelo E2E HTTP já realizado. As provas de CI e imagem devem corresponder ao SHA final deste incremento.

## Origem preservada

- Branch de trabalho: `codex/whatsapp-history-order-20261111`.
- Histórico, mídias, visibilidade por caixa e progresso: `d0d4b3139f10a0b9ff8c16f9c18c586f88b229e2`.
- A–G do LAB2: `cad427d400d824fc1fdc06c1c1079f324e7f3f6c`, consolidado em `c6eb87661bfd2dd5f50e3868f30706770b562655`.
- Runtime e Scout oficial: `d11c879a3d6e27499e1aea45736797a6e913b829`.
- Main reconferida: `d8a83b824b11cc68ddbbce7c79681f368051fb70`, ancestral. Não houve merge na main.

Cinco conflitos A–G foram resolvidos seletivamente: ação/controller de merge de contatos, controllers de contatos/pontos de contato do cadastro de clientes e `db/schema.rb`. Foram preservados os escopos de Account, restrições de grupos e recibos de histórico. O schema manteve a versão mais recente; oito triggers e uma FK idênticos duplicados foram removidos após reprodução em carga de schema descartável. Nenhuma migration aplicada foi reescrita.

O runtime mantém o formato de protocolo e o índice único por Account. A correção incorporada do Backoffice limita a dez tentativas a geração de um número automático ocupado, sem renumerar registros existentes. Ruby 3.4.12p148, Node 24.22.3 e Alpine 3.24 têm bases pinadas; Scout 5.7.0 é a única alteração adicional de versão de gem. Os metadados históricos de preparação do runtime continuam históricos, sem transferir sua aprovação para este merge.

## Evidência local e limite

Na consolidação A–G, passaram 63 exemplos Rails de histórico/mídia/visibilidade e 32 de contatos/finder/controllers. Os dois E2E HTTP anteriores usaram PostgreSQL, Redis, MinIO e Rails/Sidekiq reais de laboratório: 12 mensagens/8 anexos e, separadamente, host operacional com duas imagens. Duas Accounts na mesma instalação não são duas instalações Chatwoot nem sessão física WhatsApp.

Os contratos de lock/runtime (6 testes), guarda de build (5 testes), identidade de migrations (336 arquivos, sem colisão) e validadores Node (35 testes) passaram. Actionlint 1.7.12 com checksum fixo validou a sintaxe dos 17 workflows modificados localmente; ShellCheck será executado no runner da CI. Os testes locais Rails utilizaram Ruby 3.4.4 e não homologam o novo binário Alpine.

## Gates novos obrigatórios

`ag-native-candidate.yml` permite build/publicação somente por dispatch explícito, na branch de histórico, com SHA exato. O build depende dos testes nativos, frontend e compatibilidade. A imagem real deve passar o probe `test/jrc_runtime/image_smoke.rb`: Ruby/Node exatos, gems nativas, Vips, decimal, PDF e XLSX sem rede, sessões ou dados reais. O push GHCR é posterior ao probe e opcional. O workflow de conexões também inclui os novos specs de recepção V2 e jobs de mídia.

A primeira CI do merge `a3c10814` comprovou identidades/contrato/migrations e frontend A–G, mas falhou no fixture antigo de paginação (2 casos) e em um stub vazio do harness Ruby. O fixture passou a fornecer o membership confirmado pelo servidor em cada resposta, inclusive após load more; a autorização do produto não foi afrouxada. Paginação e 43 regressões de escopo passaram juntas (45 testes). O stub retorna nil explicitamente, sem mudar seu comportamento. A guarda do runtime admite apenas o hash exato desse fixture adicional e continua rejeitando outras mudanças funcionais.

CI do próximo SHA, build Alpine, digest publicado e deploy ainda precisam de evidência. Não reutilizar a CI do pai ou o build Vite anterior como aprovação desta candidata. Branches de outros clientes, credenciais, produção, sessões e mecanismos existentes permanecem preservados. Nenhuma rotina de backup/dump/restore foi executada.

## Release

Autorização do usuário abrange a candidata consolidada, imagens e atualização final do Broker e Grupo JRC. Só executar após os gates do SHA atual, conferência de migrations e versão efetiva do servidor. Não disparar campanha, parear número, reprocessar UNKNOWN ou ativar captura de conexões existentes como efeito do deploy. KEEP permanece.
