# JRC Conversas LAB2 — publicacao no GHCR

Pacote da aplicacao principal deste repositorio:

`ghcr.io/claudiohideki/jrc-conversas-lab2`

Execute `.github/workflows/build-ghcr.yml` manualmente no Actions com o SHA completo do commit de codigo, `component=app` e `publish=true`.

Cada versao e publicada exclusivamente com a tag `sha-<SHA completo>`. O workflow recusa sobrescrever uma tag existente. Os pacotes e imagens anteriores permanecem preservados.

Para a atualizacao do ZIP de 04/10/2026, o commit de codigo e `905d4a731996919f190830034a0ff8a64a520c37`. Alteracoes posteriores somente no workflow nao mudam esse SHA de origem.

O build usa `linux/amd64`. Apos a publicacao confirmada, use a mesma imagem nos servicos da aplicacao e do worker (`rails` e `sidekiq` no Compose do repositorio).

Antes de atualizar a instalacao, confira o backup e as migrations pendentes, incluindo `20261002173000_add_jrc_crm_organizational_structure.rb`. A publicacao da imagem nao executa migrations nem modifica o servidor.
