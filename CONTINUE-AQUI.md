# Checkpoint ativo - sincronizacao WhatsApp, 12/11/2026

Implementacao local sobre Broker bb438150060a418a7aa36a04beacf0a81a88bc3d e LAB2 ca6e7824842022bcfe4db04d6d5a359994f8540b. Preservados os incrementos e as branches atuais. Nenhum push, merge, imagem publicada, deploy, envio/pareamento/replay real, credencial alterada ou rotina de backup/dump/restore nesta rodada.

## Implementado e exercitado neste incremento

- Broker: writer nativo, peers canonicos e prova do dono; pagina e recibos/obrigacoes de projecao transacionais; migration0089 aditiva com RLS; consumidor HTTP V2 com capability, recibo correlacionado e bootstrap imutavel; lease/retry e reparo da mesma midia. V2 nunca cai no worker/live V1.
- Driver privado headless: uma pagina de origem/nativa e uma entrega por tick; filtro por runId, gate, pausa/cancelamento e ACK somente apos COMMIT. Falha da origem nao congela dados ja persistidos.
- Hook compilado da engine: resolver privado de midia persistida congelado na captura, exigindo persisted=true e scopeKey original; URL/key da origem nao entra no lote. Nao implementa download da midia nem ownership produtivo.
- Recaptura: dedupe exclui somente UUID do objeto do hash do fato; SHA/tamanho/tipo/MIME/nome/legenda continuam estritos. Projecao reutiliza mediaId canonico para manter o request imutavel e evitar anexos duplicados.
- LAB2: multipart privado, reserva antes do PUT, SHA256/MIME/leitura fisica, ATTACH_PENDING PostgreSQL e job/scheduler Sidekiq. Token original e revisao de destino continuam obrigatorios; KEEP preservado.
- Minhas: historico resolvido comprovado por recibo CHAT em caixas de membership nao exclusivas; revisao de prova invalida paginas revogadas. URA/exclusividade/supervisao e responsaveis preservados.

## Evidencias atuais

A suite geral final passou **4355/4355 testes em 570 arquivos**, com um worker. Backup.test foi explicitamente excluido por escopo; nenhuma rotina operacional dessa area foi executada.

Writer/catalogo PostgreSQL24; unidade focada16; origem/journal/engine pinada96; Rails63/7 arquivos; UI43: zero falhas nessas rodadas. Typecheck e build Broker passaram. Vite LAB2 passou com heap4096MiB em8m18s; tentativa anterior3072MiB falhou e permanece registrada. ESLint2 arquivos sem ocorrencias. RuboCop20 arquivos: uma ClassLength preexistente no Finder (208 no HEAD anterior/214 atual; limite175). A nova ocorrencia MethodLength foi corrigida. Nao se declara lint global limpo.

E2E passou com PostgreSQL de origem/Broker, Rails HTTP, Redis/Sidekiq e MinIO reais: duas Accounts/tenants isoladas na mesma instalacao Rails,12 mensagens/8 anexos (imagem+legenda, audio, PDF, video), texto incoming/outgoing e grupos/LID. Compara IDs independentes, texto/direcao/data e hashes dos bytes. Perda de ACK em ambas as fronteiras e recaptura com novas referencias convergem para os mesmos registros/anexos. Minhas retorna somente as duas conversas da caixa do membro e nega acesso cruzado. Nao e navegador E2E, duas instalacoes Chatwoot independentes nem WhatsApp real.

Lote sintetico10001 mensagens individuais/grupos em101 paginas reconciliou todos os IDs em175,14s de teste; origem reconstruida entre leituras e KEEP mantido. Nao mede SLA, projecao em larga escala ou capacidade50/400/900 sessoes. progress100/isLatest nao fabricam fechamento de cobertura.

## Bloqueios internos restantes - nao habilitar em producao

1. Host/ownership operacional e autoridade/revogacao reais ate COMMIT; o host atual e de laboratorio e deliveryOwnership=UNPROVEN.
2. Obter/descriptografar e persistir os bytes de midias da origem antes de fornecer referencias READY. Os testes fisicos iniciam com bytes sinteticos fornecidos ao storage privado.
3. Convergencia completa live/history para outbound/midia e interoperabilidade CENTRAL dos grupos. Texto incoming individual/grupo tem prova/reuso, o restante nao esta homologado.
4. Composicao/scheduler operacional, admissao por conexao e rotas/painel publico V2 de status/retomada/cancelamento. Driver e ports privados nao sao esses endpoints.
5. Browser E2E, duas instalacoes independentes, imagem efetiva da engine/CI do novo SHA e sessao real autorizada com inventario da cobertura disponivel. Nao prometer copia integral do celular.

Mains reconferidas em12/11: Broker29095bea35702893e1a5b80f5131bdd13b901a7e e LAB2d8a83b824b11cc68ddbbce7c79681f368051fb70 continuam ancestrais. Broker compartilhado; LAB2 base completa; Branef/GLPI e GoPure nao alterados. Producao nao inspecionada nem modificada neste incremento.

Relatorio/evidencias locais: C:/Users/DEV02/Documents/ChatGPT/New project/output/broker-whatsapp-sync-20261112.

---
# Continuação — histórico WhatsApp, 11/11/2026

Branch: `codex/whatsapp-history-order-20261111`; base preservada `126d251dd5d5179783706f4934ba4fabc9d12b19`. Main verificada: `d8a83b824b11cc68ddbbce7c79681f368051fb70`, já ancestral da candidata. Não substituir pela main antiga nem copiar código de Branef/GLPI. Broker é produto separado e compartilhado.

Este incremento conclui localmente o escopo pessoal por caixas, paginação/relógio do histórico existente e o receptor silencioso V2 de texto/grupos. Receptor default off (`JRC_HISTORY_SYNC_V2_ENABLED`), sem mídia V2 anunciada. Contrato, invariáveis, migration, testes e limites: `docs/jrc-broker/history-sync-v2.md`. Plano preservado: `docs/superpowers/plans/2026-11-11-whatsapp-history-order.md`.

Evidências atuais: **228 Rails / 15 arquivos, 65 JS / 5 arquivos, zero falhas**. ESLint dos 7 arquivos frontend alterados: exit0. RuboCop dos 12 arquivos novos/de testes principais: zero ocorrências. Lint do core comparado ao HEAD anterior preserva violações preexistentes, inclusive ClassLength; não se afirma lint global limpo. Build frontend do mesmo código UI passou e manifesto físico foi conferido no incremento anterior. Nenhuma imagem foi gerada/publicada nesta rodada.

Regressões reproduzidas e corrigidas: histórico não avançava a lista; Minhas recebia caixas fora do membership; ordem empatada instável; adoção sem comprovação de dono/provedor/participante; status de mensagem podia regredir; grupos vazavam por busca/exportação/diretórios/links; segundo vínculo de grupo na mesma caixa; merge de contato deixava recibos sem referência. Grupo usa source_id canônico `jrc-group-<scope>`; contatos normais continuam compartilhados conforme o contrato existente.

Migration nova e não aplicada em produção: `20261111170000_create_jrc_broker_history_receipts.rb`. Pausar por flag, preservar recibos, não executar DOWN destrutivo. Contas, sessões, credenciais, atribuições e configurações produtivas não alteradas. Não houve envio, replay, conexão real, deploy, push/merge, backup/dump/restore.

Próximo passo no plano conjunto: writer canônico e catálogo do Broker, transporte autenticado da origem, projeção com negociação/recibos, mídia privada física e job Sidekiq, progresso nos dois produtos e E2E. A existência deste receptor não traz automaticamente tudo do telefone; validar cobertura real da origem e não considerar Baileys isLatest como conclusão da captura.

Evidências locais detalhadas: `C:/Users/DEV02/Documents/ChatGPT/New project/output/broker-whatsapp-sync-20261111/lab2-v2`. Worktree Broker ativo: `C:/Users/DEV02/.codex/worktrees/broker-whatsapp-history-sync/consolidacao-20261109`, branch `codex/whatsapp-history-sync-20261111`. Preservar outros checkouts e trabalhos de áudio/conexões anteriores.
