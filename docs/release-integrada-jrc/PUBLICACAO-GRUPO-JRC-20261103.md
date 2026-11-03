# Grupo JRC — publicação verificada em 03/11/2026

O JRC Conversas Grupo JRC foi atualizado. Fonte executável aprovada: `edd6f1a2570676a64d0e9086652c8e1da476c7ac`, branch `codex/lab2-integral-20261102`. Este registro documental é posterior ao deploy; não representa outra alteração executável nem exige repetir a publicação.

## Fonte consolidada

- Base preservada: 20e56104ec0f748b53da58edb1b639369fad0a1e; produção anterior: daae59ecdbfd28008773a8adf9ec13f34ac8f486.
- Commit 183b58e85701d8ac9a5c4918bd6e839155221372: 185 arquivos, 9.454 adições/183 remoções. Preserva os incrementos locais de conexões/distribuição/auditoria, Flow, Central de Migração, NICO e custódia de mídia, juntamente com Atendimento, Campanhas, CRM, Projetos e Service Desk já publicados.
- Commit edd6f1a2:fixture MinIO da CI obtida do release oficial, pinada por SHA256 e verificada antes de executar. Nenhuma mudança no storage produtivo.
- Fetch explícito de todas as branches, repetido antes da promoção: nenhuma atualização de outro desenvolvedor posterior às já incorporadas. Os quatro commits de 26/10 já possuem equivalentes na base; nenhum cherry-pick duplicado.
- Nenhum merge na main, reset, clean ou force push.

## Imagem e testes

Imagem implantada:

```text
ghcr.io/claudiohideki/jrc-conversas-lab2@sha256:dabbbfcad2a97c659fb90c269b3e96a7f7c619fe70d8d56800486023c9ce4a76
```

Tag: `sha-edd6f1a2570676a64d0e9086652c8e1da476c7ac`.

- [CI nativa do SHA aprovado](https://github.com/ClaudioHideki/jrc-conversas-lab2/actions/runs/41645392552):SUCCESS nos dois jobs. 818 exemplos de contratos/integridade; 4 MinIO físico; 134 testes UI; Sidekiq real com persistência de recibo, perda de ACK e recuperação após crash. Frente comercial: 1.322 exemplos principais + 20 de concorrência + 220 de integrações. O plano de 1.342 exemplos foi reconciliado sem omissões, duplicações ou pendências. Minitest adicional: 18, 3 e 16 casos, todos sem falhas.
- [Build e publicação](https://github.com/ClaudioHideki/jrc-conversas-lab2/actions/runs/41645896885):SUCCESS. 1.882 testes frontend em 178 arquivos. 129 arquivos do produto/17 migrations conferidos dentro da imagem; SHA interno, label e plataforma validados. Rails/Sidekiq da mesma imagem inicializados em ambiente isolado, com heartbeat, storage compartilhado e OCR/PDF real enfileirado.
- Digest confirmado independentemente no GHCR com `docker buildx imagetools inspect`.
- Local: 239 exemplos Rails/0 falhas/0 pending, 134 UI e 4 MinIO, sem somar esses testes novamente aos da CI. Banco frio + migrations203000–205000 validado. ESLint focal:0 erros/12 avisos. RuboCop dos 3 gates novos: 0 ocorrências. Gates Node e revisão independente aprovados.
- A primeira CI 183b58e passou 818 exemplos, mas falhou ao baixar a fixture antiga do Docker Hub. Seu build foi recusado pelo gate de CI e não publicou imagem. O novo SHA repetiu e aprovou todos os gates.

## Dokploy e conferência produtiva

Serviço `grupojrcconversas-z0edle`, JRC Conversas Grupo JRC. Compose completo: 125 linhas; somente a referência da imagem foi alterada, comparada integralmente no editor e conferida novamente após salvar/recarregar. ENV não foi editado. Preservados volumes, redes e recursos declarados: Rails 2 CPU/3G, Sidekiq 1 CPU/2G, init 1 CPU/1G.

O deploy terminou com sucesso. Containers observados:

| Serviço | Container | Resultado |
|---|---|---|
| Rails | bc16920b5640 | running; SHA edd6f1a2 |
| Sidekiq | 50b51ecfc39b | running; SHA edd6f1a2; 1 processo com heartbeat |
| Init | 84576b1ecbcf | Exited(0) |
| Base | 33d659d2be1c | Exited(0) |

Endpoint público HTTPS `/health`:200, corpo `{"status":"woot"}`. O HTTP interno redireciona 301 para HTTPS; não foi tratado como falha da aplicação.

As sete migrations novas estão no ledger e não há pendentes:

1.20261102120000 — eventos de conexão Broker.
2.20261102130000 — Central de Migração.
3.20261102201000 — escopo de inspeção Flow.
4.20261102202000 — auditoria de migrações.
5.20261102203000 — ledger de mídia.
6.20261102204000 — identidade/ausência física e fencing de scanner.
7.20261102205000 — CHECK de identidade NULL-safe.

Versão final 20261102205000; os dois triggers de ownership de mídia foram consultados no PostgreSQL produtivo. O init existente `db:chatwoot_prepare` foi preservado; `dump_schema_after_migration=false` em produção.

## Validação de interface e limites

- Campanhas: carregou após o deploy com 17 campanhas no período e 52 envios já existentes; não houve disparo de teste. Sete falhas históricas continuam visíveis; a atualização não as apagou nem reprocessou.
- Conexões WhatsApp: rota publicada carregou, incluindo controles de distribuição e histórico. Nenhum número foi conectado ou desconectado.
- Central de Migração: rota carregou e apresentou os 10 destinos disponíveis. Nenhum lote, importação ou alteração de clientes foi criado durante a conferência.
- Sem erros registrados no navegador nas verificações das duas rotas novas. Isso não equivale a testar todas as jornadas com dados reais.

Broker permanece na publicação independente anterior d1d0f2e6d7812865c39b1250454e238231b720b2; não houve novo deploy de Broker/engine Evolution neste incremento.

Não foram executados backup, dump, restore, migração de números, envio real de teste, pairing ou replay de FAILED/UNKNOWN. NICO com provedor pago, entrega operacional de campanhas, homologação CCLX e capacidade 50/400/900 não foram declarados 100% validados por esta publicação.

## Recuperação e evidências

Imagem anterior preservada como referência: `ghcr.io/claudiohideki/jrc-conversas-lab2@sha256:bf68a7b19a2d7ad23d41f18a5370a58116aaca5c893389a873252400bd9d5eb9`. Não foi executado rollback. As migrations de custódia são irreversíveis; qualquer reversão de binário deve conservar o banco expandido e avaliar jobs/contratos novos, sem executar down ou apagar evidências.

Evidências locais: `output/lab2-release-20261103/` no workspace principal, com estado, consultas produtivas somente leitura, resultados locais e screenshot dos containers. Não contém ENV nem credenciais produtivas.
