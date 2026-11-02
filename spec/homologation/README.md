# Sidekiq real / obrigação Broker — laboratório somente

Os scripts `broker_sidekiq_*` abaixo recusam ambiente diferente de Rails test e banco diferente de `jrc_durable_review_test`. São executáveis explícitos de homologação; não são jobs produtivos nem RSpec com adapter falso.

Preparação: código LAB2 atual com migrations em PostgreSQL/pgvector descartável, Redis exclusivo e rede interna sem portas públicas. Não usar banco/Redis compartilhados. O laboratório desta rodada materializou apenas arquivos versionados num diretório vazio, sem .env privado.

1. Com Rails test e o banco exato, execute `bundle exec rails runner spec/homologation/broker_sidekiq_control.rb seed`. A fase cria duas contas sintéticas, uma obrigação por conta e publica na fila exclusiva `broker_homologation_20261102` usando adapter Sidekiq real.
2. Execute `LAB_KILL_AFTER_RECEIPT=1 bundle exec ruby spec/homologation/broker_sidekiq_worker.rb`. O worker usa concurrency1, somente a fila acima. Após INSERT real do primeiro recibo PostgreSQL, recebe SIGKILL; exit137 esperado. A obrigação continua running.
3. Execute `bundle exec rails runner spec/homologation/broker_sidekiq_control.rb recover`. Ela faz expirar controladamente o lease do teste e publica jobs de recuperação e duplicados. Essa alteração do relógio do fixture não comprova o decurso real de cinco minutos.
4. Inicie outro worker com `LAB_KILL_AFTER_RECEIPT=0`. Execute `bundle exec rails runner spec/homologation/broker_sidekiq_control.rb verify`. O observador usa leitura uncached, pois outro processo modifica o banco.
5. Pare apenas os recursos deste laboratório, preservando volumes. Não há limpeza automática ou remoção de dados no script.

O worker carrega Rails antes de exigir Sidekiq CLI e aborta se Rails já iniciou em modo servidor. Assim a condição de carregamento do cron geral não é executada durante o boot; não se iniciam os agendamentos globais. Nenhum Sidekiq compartilhado foi iniciado ou alterado. Filas fora do nome exclusivo não são consumidas.

O transporte SafeFetch é substituído somente no processo do probe por uma porta sintética que aceita o destino exato de fixture. Ela persiste recibos em tabela de laboratório, confere hash/account/delivery e pode morrer após esse COMMIT. Não há HTTP real, TLS, WhatsApp ou integração CCLX nesse transporte. O receptor idempotente é modelado, embora seu PostgreSQL seja real.

Resultado observado: Rails7.1.5.2, Sidekiq7.3.1 e Redis reais; duas obrigações delivered; tentativas2/1; dois recibos, cada um ligado à sua conta. A primeira verificação expirou por query cache do observador; consulta SQL independente demonstrou os estados corretos e a verificação uncached passou sem reenviar. Logs RED/erro do observador e GREEN são preservados.

Limites: duas contas na mesma instalação, não duas instalações Chatwoot independentes. Não valida perda de Redis, ACK do HTTP real, codecs/mídias, configuração do CCLX, capacidade ou sessão física. Não executa backup, dump ou restore.

## Prova adicional com HTTPS e Broker reais

O incremento separado [`broker_https_*`](broker_https_README.md) usa dois bancos Rails frios com IDs locais coincidentes, Redis DB0/1, TLS com CA validada e a rota real do Broker na imagem oficial fixada por digest. Não substitui o probe sintético acima nem modifica seu transporte.

Run `e4603a88-5311-42e9-b3d2-319cdeae8f5a`: launcher exit0; TLS confiável aceito, CA/hostname inválidos rejeitados, assinatura cruzada401, indisponibilidade após COMMIT do produtor, ACK retido após COMMIT do receptor e Sidekiq SIGKILL137. Retomada real: A delivered/3, B delivered/2; uma observação e um job por organização, RLS cruzado0 e UUID/hash preservados. Lease expirada controladamente apenas na fixture. Jobs físicos permaneceram PENDING.

[Evidência sanitizada](../../docs/release-integrada-jrc/evidence/broker-https-custody-20261102.json). O stack foi executado antes dos ajustes finais de estilo Ruby; unidade9/19, RuboCop6arquivos/0ofensas, sintaxe e certificados foram verificados depois. Isso não atribui o gate completo ao SHA deste commit. Não homologa WhatsApp físico, Chatwoot stock/CCLX ou boot completo de produção.

Rodada fria final posterior: `bb759c3f-76e6-4f87-a9a8-d57d172276b3`, exit0, código exato `f1ffd1b9de2bc773ad8c1983f25f1dd352579bb5`, com13hashesLF/Git blobs conferidos e cópia materializada idêntica. Inclui estilo final e cleanup fail-closed:15contratos sem Docker, containers parados e Rails desanexado confirmados antes do resultado. A delivered/3, B delivered/2; uma observação/um job por org, RLS cruzado0. [Evidência final sanitizada](../../docs/release-integrada-jrc/evidence/broker-https-custody-final-20261102.json). O commit posterior é somente documentação, sem alterar bytes executáveis da fixture. Os limites físicos/CCLX acima permanecem.
