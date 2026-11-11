# Continuação — histórico WhatsApp, 11/11/2026

Branch: `codex/whatsapp-history-order-20261111`; base preservada `126d251dd5d5179783706f4934ba4fabc9d12b19`. Main verificada: `d8a83b824b11cc68ddbbce7c79681f368051fb70`, já ancestral da candidata. Não substituir pela main antiga nem copiar código de Branef/GLPI. Broker é produto separado e compartilhado.

Este incremento conclui localmente o escopo pessoal por caixas, paginação/relógio do histórico existente e o receptor silencioso V2 de texto/grupos. Receptor default off (`JRC_HISTORY_SYNC_V2_ENABLED`), sem mídia V2 anunciada. Contrato, invariáveis, migration, testes e limites: `docs/jrc-broker/history-sync-v2.md`. Plano preservado: `docs/superpowers/plans/2026-11-11-whatsapp-history-order.md`.

Evidências atuais: **228 Rails / 15 arquivos, 65 JS / 5 arquivos, zero falhas**. ESLint dos 7 arquivos frontend alterados: exit0. RuboCop dos 12 arquivos novos/de testes principais: zero ocorrências. Lint do core comparado ao HEAD anterior preserva violações preexistentes, inclusive ClassLength; não se afirma lint global limpo. Build frontend do mesmo código UI passou e manifesto físico foi conferido no incremento anterior. Nenhuma imagem foi gerada/publicada nesta rodada.

Regressões reproduzidas e corrigidas: histórico não avançava a lista; Minhas recebia caixas fora do membership; ordem empatada instável; adoção sem comprovação de dono/provedor/participante; status de mensagem podia regredir; grupos vazavam por busca/exportação/diretórios/links; segundo vínculo de grupo na mesma caixa; merge de contato deixava recibos sem referência. Grupo usa source_id canônico `jrc-group-<scope>`; contatos normais continuam compartilhados conforme o contrato existente.

Migration nova e não aplicada em produção: `20261111170000_create_jrc_broker_history_receipts.rb`. Pausar por flag, preservar recibos, não executar DOWN destrutivo. Contas, sessões, credenciais, atribuições e configurações produtivas não alteradas. Não houve envio, replay, conexão real, deploy, push/merge, backup/dump/restore.

Próximo passo no plano conjunto: writer canônico e catálogo do Broker, transporte autenticado da origem, projeção com negociação/recibos, mídia privada física e job Sidekiq, progresso nos dois produtos e E2E. A existência deste receptor não traz automaticamente tudo do telefone; validar cobertura real da origem e não considerar Baileys isLatest como conclusão da captura.

Evidências locais detalhadas: `C:/Users/DEV02/Documents/ChatGPT/New project/output/broker-whatsapp-sync-20261111/lab2-v2`. Worktree Broker ativo: `C:/Users/DEV02/.codex/worktrees/broker-whatsapp-history-sync/consolidacao-20261109`, branch `codex/whatsapp-history-sync-20261111`. Preservar outros checkouts e trabalhos de áudio/conexões anteriores.
