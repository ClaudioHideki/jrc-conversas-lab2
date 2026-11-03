# Release consolidada LAB2 / Grupo JRC — 03/11/2026

Pedido vigente: integrar nossas alterações às últimas atualizações publicadas, validar e publicar em produção. Preservar o worktree `codex/lab2-integral-20261102`, base `20e56104`, e todo WIP existente. Não fazer merge automático na main. Não enviar mensagens reais, parear números ou reprocessar UNKNOWN. Backup/dump/restore fora do escopo.

## Task 1 — Fechar os gates de banco e mídia

- Reproduzir os gaps do workflow: branch candidata ausente e preparo que altera schema.rb.
- Criar regressão Node dos gates, helper Rails de aplicação de migrations somente em banco de teste e prova de schema frio seguida das migrations 203000–205000.
- Validar o importador com ActiveStorage S3 e MinIO físico isolado: integridade, persistência, KEEP e retry. Não usar storage produtivo.
- Incluir essas suítes no workflow nativo, preservando os gates existentes.

## Task 2 — Consolidar e validar

- Revisar diff completo e executar Rails afetados, frontend, lint, contratos, build e revisão independente da branch.
- Atualizar checkpoint e evidências com resultados reais. Commitar seletivamente código/testes/documentação, sem arquivos secretos ou logs locais.
- Buscar novamente todas as branches antes de publicar e reconciliar novidades equivalentes sem cherry-pick cego.
- Publicar branch candidata e exigir CI verde no SHA exato.

## Task 3 — Imagem e promoção

- Gerar imagem app pelo workflow versionado, gate nativo obrigatório e smoke Rails/Sidekiq da própria imagem.
- Conferir SHA, digest, migrations e compatibilidade. Registrar imagem anterior.
- Atualizar somente imagem do Grupo JRC no Compose completo, preservando ENV, recursos e volumes. Aplicar migrations necessárias pelo processo controlado de release e verificar Rails/Sidekiq no mesmo SHA.
- Validar jornadas somente leitura, saúde e ledger de migrations. Registrar limites de homologação operacional.

Pre-flight: Task 1 fornece preparo de banco para Task 2/3; o schema Ruby não representa funções SQL de ownership. Ruling: carregar o schema existente e executar migrations pendentes sem gerar dump — preserva os guards e detecta falhas de inicialização fria. Autorização de publicação/deploy já consta do pedido vigente.
