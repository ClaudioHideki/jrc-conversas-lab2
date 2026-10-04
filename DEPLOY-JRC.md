# JRC Conversas LAB2 — publicacao no GHCR

Pacote da aplicacao principal deste repositorio:

`ghcr.io/claudiohideki/jrc-conversas-lab2`

Execute `.github/workflows/build-ghcr.yml` manualmente no Actions com o SHA completo do commit de codigo, `component=app` e `publish=true`.

Cada versao e publicada exclusivamente com a tag `sha-<SHA completo>`. O workflow recusa sobrescrever uma tag existente. Os pacotes e imagens anteriores permanecem preservados.

A atualizacao de Pedidos usa a branch `codex/crm-pedidos-integridade-20261004`. Informe como `source_sha` o SHA completo publicado dessa branch, sem reutilizar tags antigas.

Imagem anterior preservada para rollback: `ghcr.io/claudiohideki/jrc-conversas-lab2:sha-905d4a731996919f190830034a0ff8a64a520c37`.

O build usa `linux/amd64`. Apos a publicacao confirmada, use a mesma imagem nos servicos da aplicacao e do worker (`rails` e `sidekiq` no Compose do repositorio).

Antes de atualizar a instalacao, confira o backup e as migrations pendentes, incluindo `20261004170000_complete_jrc_customer_master_company_profile.rb` e `20261004183000_strengthen_sales_order_origin_and_audit.rb`. A primeira e deliberadamente irreversivel para nao descartar dados comerciais; a segunda possui `down`. Rollback da imagem nao reverte o banco.

O workflow valida as migrations e o RSpec somente no PostgreSQL descartavel do runner. A publicacao da imagem nao executa migrations em producao nem modifica o servidor.
