<!-- jrc-operational-init:v1 -->
# Modelo de dados — JRC Conversas LAB2 — URA LAB

## Fontes e nível da evidência

Documentação inicial com base na árvore local; nenhum banco de clientes foi consultado ou alterado.

Fonte estrutural: [db/schema.rb](../../db/schema.rb). Tabelas confirmadas no schema local: `accounts`, `users`, `account_users`, `inboxes`, `inbox_members`, `contacts`, `contact_inboxes`, `conversations`, `messages`, `teams`, `team_members`, `active_storage_blobs`, `active_storage_attachments`.

A lista é um recorte de contexto, não um catálogo de todas as tabelas ou prova das migrations aplicadas no servidor. Conferir índices, chaves e políticas nos modelos/schema antes de alterar relações.

## Fontes de continuação

- [AGENTS.md](<../../AGENTS.md>)
- [README.md](<../../README.md>)
- [package.json](<../../package.json>)
- [Gemfile](<../../Gemfile>)
- [db/schema.rb](<../../db/schema.rb>)

## Regras de evolução

- Distinguir schema declarado de schema aplicado.
- Preservar histórico e compatibilidade de contratos; não renumerar uma migration já aplicada.
- Registrar mudanças relevantes e seu impacto no ADR, com critério de aceite e validação autorizada.
