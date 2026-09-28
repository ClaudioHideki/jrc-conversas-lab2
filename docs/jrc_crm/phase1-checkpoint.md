# Checkpoint CRM — Fase 1

Baseline preservada: `b97425df77a73794973efc7c261e3d67d7f47724`.

## Escopo

- Paginação de contatos com desempate por ID, avanço correto e retry da busca sem saltar páginas.
- Contato existente → criação/reutilização de lead visível. Permissão individual CRM, escopo de conta e políticas existentes preservados. Vínculos legados ambíguos retornam conflito; não são mesclados.
- Filtros locais de atividades por busca, tipo, responsável e estado, sobre registros autorizados pela API. Cores semânticas, contadores e seleção usam o design system JRC.
- Gestão de equipe conectada às métricas existentes, com período/busca e acesso restrito a administradores.

O novo ponto de entrada de criação de lead reconsulta sob lock do contato e utiliza o índice existente de conta/idempotency_key. Não altera os fluxos de conversa, criação manual ou NICO, nem impõe unicidade global por contato. Concorrência com transações reais ainda precisa de validação.

Não há alteração de schema/migrations, Softphone universal, bridge, permissões existentes, NICO ou infraestrutura. Nenhum outro domínio comercial foi portado. Funcionalidades coloridas e indicadores são preservados; identidade corporativa de outros clientes não faz parte deste porte.

## Validação registrada em 25/09/2026

| Verificação | Resultado |
|---|---|
| CRM/contatos | 91 testes aprovados, incluindo filtros, cores, contadores e seleção |
| Desktop universal | 40 testes aprovados |
| Webphone/bridge/download | 88 testes aprovados |
| NICO frontend | 61 testes aprovados |
| NICO runtime | 22 passaram; 6 falharam no ambiente local pela dependência `@elizaos/core` ausente; código não alterado |
| Request specs Rails adicionados | 11 exemplos pendentes de ambiente seguro de teste |
| Sintaxe Ruby | 7 arquivos aprovados |
| Lint | Novos arquivos sem infrações; permanecem problemas legados nas telas de contatos/atividades e nos dois controllers existentes |
| `git diff --check` | Aprovado |

Para executar a suíte frontend específica, configurar `TZ=UTC` e usar:

```sh
node node_modules/vitest/vitest.mjs run --config vitest.crm-phase1.config.mjs --no-cache --no-coverage
```

Os request specs pendentes estão em `spec/requests/api/v1/accounts/contacts_pagination_spec.rb`, `spec/requests/api/v1/accounts/crm/contact_leads_spec.rb` e `spec/requests/api/v1/accounts/crm/management_spec.rb`. O helper Rails atual chama `ActiveRecord::Migration.maintain_test_schema!`; não executar em ambiente com restrição de migrations ou conectado a banco compartilhado/produção. Esses testes não foram executados nesta entrega, e não comprovam ainda a concorrência real.

Este checkpoint não implica build, publicação de artefatos ou deploy.
