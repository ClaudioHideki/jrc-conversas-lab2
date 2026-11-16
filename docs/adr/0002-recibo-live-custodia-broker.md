# ADR 0002: Recibo imutável de custódia LIVE

- **Status:** Aceita para implementação local; publicação não autorizada
- **Data:** 2026-11-16
- **Autores:** responsável pelo incremento JRC/Broker e implementação LAB2

## Contexto

O POST genérico não permite provar um COMMIT cuja resposta se perdeu. Marcadores editáveis não são recibos. O histórico V2 não pode substituir a entrada LIVE: seus callbacks são deliberadamente silenciosos. O desenho aprovado está no Broker em `docs/implementation/live-ingress-receipt-v1-20261116.md`.

## Decisão tomada

Adicionar `jrc-live-ingress/1`, autoridade por token administrador e binding atual, hash JSON canônico, recibo PostgreSQL com chave única de origem e identidade protegida por trigger. Texto usa MessageBuilder normal na transação do recibo. LIVE outgoing não representa ator humano.

Mídia reserva `MEDIA_PENDING` sem message_id, escrow bytea privado de até16MiB/arquivo e64MiB/Account sob lock. Executor recebe somente ID, revalida token original/escopo antes do acesso privado e antes do COMMIT. Após leitura física SHA/size/MIME, mensagem normal e PERSISTED são confirmados juntos; só então o escrow é liberado. Objetos existentes corrompidos não são sobrescritos. Scheduler cobre perda do enqueue. Não há expiração ou limpeza de objetos KEEP.

Para interoperabilidade, novas recepções V2 guardam `origin_context` imutável; antigas ficam NULL. Um lock comum de origem precede os locks protocolares. Reuso requer recibo, escopo físico exato, mesma conversa/direção/conteúdo canônico e bytes privados verificados. A apresentação de grupo é construída deterministamente com participante exato; não há remoção arbitrária de prefixos. Reuso preserva mensagem, atributos, timestamp e callbacks silenciosos; status só avança monotonicamente. Arquivos com nomes normalizados podem coincidir somente quando MIME/size/hash e leitura física coincidem.

O V2 não afirma a origem LIVE/EXTERNAL_OBSERVED. Na adoção V2→LIVE, a origem do novo pedido determina a apresentação que deve coincidir exatamente com o conteúdo canônico preservado. Isso prova custódia do mesmo fato; não concede intenção humana, ownership, transição de bot ou permissão de reenvio. Nenhuma evidência é fabricada para recibos V2 antigos.

O campo opcional `occurred_at` entra no hash somente quando presente, aceita Unix inteiro de0 até relógio servidor+5min e define created_at antes do SAVE normal. Conversa vazia recebe a primeira âncora de origem sob lock; atividade existente só avança por CAS e o objeto é recarregado antes do websocket. O parâmetro created_at da API genérica continua sem autoridade.

Custódia e cronologia usam relógios distintos. `published_at` é gravado pelo servidor junto da criação LIVE normal ou da conclusão da mídia; depois de PERSISTED é imutável. Adoção histórica e recibos antigos permanecem NULL, sem backfill. Não lidas usam COALESCE(publicação comprovada, created_at), com fence de Account e índice por message_id, tanto nas helpers/listagens quanto nos quatro serviços de badges/cache/filtros. O cursor manual usa o último incoming por publicação, com fallback genérico. A janela24h continua usando a origem; widget/contact-side e mailer não foram ampliados por este incremento de API inbox.

## Consequências

- Recibo de custódia não é entrega WhatsApp; UNKNOWN antigo sem prova nativa continua bloqueado.
- FKs restritivas preservam recibos/mensagens/objetos. Exclusão física de Account/Inbox/Message/Blob pode ser rejeitada. Compatibilidade do fluxo de hard delete/expurgo permanece **bloqueio de revisão pré-release**; não foi alterado neste incremento. Desconectar/remover conexão preservando histórico é uma operação distinta.
- Reversão operacional pausa admissão/executor, mantém tabela, recibos, escrow e objetos; migration down é irreversível. Não executar purge/cascade como rollback.
- Aplicar a migração aditiva antes de iniciar este binário/worker. Um binário antigo não interpreta o relógio de publicação dos novos eventos retrodatados; rollback completo exige conservar a leitura compatível ou tratar esse limite, sem apagar provas.
- Testes locais Ruby3.4.4 não homologam runtime produto3.4.12. Build frontend local permanece bloqueado pelos guardas de recursos já documentados. Não houve produção, pareamento, envio físico, backup, dump ou restore.

## Evidência e validação

Regressões: `spec/requests/jrc_broker_live_ingress_spec.rb`, `spec/services/jrc_broker/live_history_interop_spec.rb` e `spec/services/jrc_broker/live_ingress_concurrency_spec.rb`. Checkpoint/evidências no diretório local `output/whatsapp-delivery-reliability-20261116/lab2`; o checkpoint final distingue RED/GREEN, E2E HTTP, build bloqueado e aceite físico não realizado.
