> **Incremento local de 12/11/2026:** base LAB2 ca6e782, alterações ainda não publicadas. Migration adicional 20261112120000, mídia física e visibilidade de histórico resolvido em caixas pessoais implementadas. Consulte o checkpoint de 12/11 em CONTINUE-AQUI.md para resultados atuais; os 228/65 casos de 11/11 abaixo são evidência histórica.

# Histórico WhatsApp V2 — receptor LAB2 em desenvolvimento

## Estado

Implementação aditiva local. Não publicada nem habilitada em produção. O protocolo V1 continua disponível. Requer `JRC_HISTORY_SYNC_V2_ENABLED=true`, o recurso `jrc_broker` da Account e os vínculos existentes. O padrão é desligado. A flag do Broker `HISTORY_SYNC_V2_ENABLED` é distinta e não habilita este receptor.

O receptor confirma texto, grupos e mensagens de mídia privada no contrato V2. O upload reserva uma intenção durável antes do PUT; a mensagem continua MEDIA_PENDING até verificação física e vínculo do anexo por Sidekiq. Não captura o telefone nem dispara envio, bot, campanha, SLA, atribuição, notificação ou webhook live durante o backfill.

## Contrato efetivamente implementado neste código

Autenticação pelo header `api_access_token` de um User administrador atual da Account, utilizada exclusivamente no backend da integração. A autoridade de conta, usuário, token e membership fica bloqueada até COMMIT. Cada chamada verifica organização, integração, inbox, instância vinculada e revisão do destino. Não há segredo do Broker no navegador.

Prefixo local: `/api/v1/accounts/:account_id/jrc_history_sync/v2/inboxes/:inbox_id`.

| Método | Caminho | Resultado |
|---|---|---|
| GET | prefixo | Capacidade autorizada: texto, grupos, mídia até 16 MiB e bootstrap silencioso |
| POST | prefixo`/bootstrap` | Contato, vínculo canônico e conversa; ou reuso de uma conversa explicitamente mapeada |
| POST | prefixo`/messages` | Mensagem histórica TEXT/MEDIA e recibo na mesma transação; mídia pode permanecer MEDIA_PENDING |
| POST | prefixo`/media` | Multipart privado: scope, metadata e file; objeto STORED não equivale a anexo confirmado |
| GET | prefixo`/receipts/:receipt_id` | Reconciliação de recibo após resposta perdida |

Escopo obrigatório: `organization_id`, `integration_id`, `instance_id`, `destination_revision`, `history_account_identity`. O request é estrito: campos desconhecidos ou incorretos são recusados; JSON limitado a 32 KiB; o multipart de midia possui limite proprio de 16 MiB mais overhead limitado. IDs UUID e timestamps Unix são validados. A configuração produtiva e as credenciais existentes não são alteradas por esta implementação.

Bootstrap acrescenta `broker_contact_id`, `broker_conversation_id`, `recipient`, `occurred_at`, `conversation_id`. `recipient` é INDIVIDUAL com JID PN/LID, ou GROUP com JID real e `group_scope` de 64 caracteres hexadecimais. `conversation_id` deve ser informado quando já existe uma conversa live mapeada; o receptor recusa adivinhar entre conversas anteriores.

Mensagem acrescenta `broker_conversation_id`, `broker_message_id`, `provider_message_id`, `content: {type: "TEXT", text: "..."}`, `direction`, `participant_jid`, `occurred_at`, `status`. `participant_jid` é obrigatório em entrada de grupo e não vira telefone de contato. Estados aceitos: sent, delivered, read e failed. Uma observação atrasada não regride read para delivered.

Resposta de persistência: `protocol: "jrc-history-sync/2"`, `state: "PERSISTED"`, envelope autorizado, `receipt_id`, `request_hash`, `contact_id`, `source_id`, `conversation_id`, IDs Broker e `message_id` quando aplicável. `conversation_id` é o display_id público. Grupo usa `source_id = jrc-group-<group_scope>` compatível com o contrato central existente. Recibo retorna somente após commit; isto não é recibo de entrega ao WhatsApp nem custódia física de mídia.

## Integridade e visibilidade

- Recibos únicos por Account/inbox/integração/identidade lógica/tipo/ID de origem. Replay com conteúdo conflitante é recusado.
- Mensagem já existente é adotada somente se Broker ID, dono histórico, provider ID, participante, inbox, conversa, direção, texto e timestamp coincidirem; anexos ou prova ausente bloqueiam a adoção. Metadados JSON serializados desta base são tratados corretamente.
- Conversa histórica nova fica resolvida e sem responsável/bot/time. Conversa existente preserva estado, responsável, time e relógios operacionais; somente `last_activity_at` avança para uma mensagem realmente mais recente.
- Grupos não entram no cadastro de pessoas/Clientes. Busca, leitura, links de contatos, exportação e criação de conversa respeitam a visibilidade de conversa/inbox, inclusive em Enterprise.
- O grupo mantém um único ContactInbox canônico, inclusive dentro da mesma inbox. Não pode ser copiado para outra caixa nem mesclado com pessoa.
- Mesclagem explícita de contatos normais transfere as referências dos recibos, preservando mensagem, dono, hashes e histórico. Não há limpeza automática de registros.
- Minhas/Minhas e compartilhadas usam `inbox_scope=member` antes da paginação. Todas continua administrativa. Realtime usa a mesma lista de membership. Exclusividade, supervisão, URA e permissões existentes permanecem autoridades; membership não libera conversa restrita.

## Migration e pausa

`20261111170000_create_jrc_broker_history_receipts.rb` cria a tabela de recibos, índices de unicidade, constraints e FKs. Validada em PostgreSQL/Redis descartáveis com Rails real. Não aplicada em produção. Nenhuma migration anterior foi renumerada; schema mais recente preservado.

Pausa: desligar a flag e interromper admissão/projeção V2. Dados ficam preservados. DOWN é irreversível intencionalmente; não remover recibos para voltar ao comportamento anterior. FKs permitem a exclusão explícita normal de entidades; o incremento não executa exclusão de dados.

Pausa do recurso não equivale a downgrade de imagem. Depois que grupos forem importados, uma candidata de rollback deve conservar os filtros de privacidade de grupos nos endpoints de contatos/busca/exportação e o tratamento dos recibos. Uma imagem antiga sem esses filtros não foi homologada como rollback seguro. O procedimento deste incremento é manter o binário compatível e desligar apenas a admissão V2.

## Evidências locais de 11/11/2026

- RED antes de implementar: 6 falhas de rotas ausentes. Casos de revisão reproduziram adoção conflitante, vazamento de grupo, fonte JSON incompatível, vínculo em outra caixa e segundo vínculo na mesma caixa.
- Última regressão Rails: **228 exemplos, zero falhas**, 15 arquivos. Cobre V1/V2, Finder OSS/Enterprise, caixas pessoais, compartilhamento/URA, Contacts/Search/Export/Merge e ContactInbox.
- 65 exemplos JS/5 arquivos e ESLint focal; build frontend Vite e manifesto verificados no incremento da lista. São evidências de aplicação local, não de uma sessão WhatsApp real.
- Lint comparado ao HEAD anterior: os controllers/finder já excediam ClassLength. O incremento acrescenta escopo e proteção de grupos; não se afirma lint global limpo. Arquivos novos são verificados separadamente.

Evidências detalhadas na raiz de coordenação `output/broker-whatsapp-sync-20261111/lab2-v2`. Ainda pendentes: writer canônico e transporte completo no Broker, captura autenticada operacional, mídia física/S3/Sidekiq, projeção com negociação/recibos, UI de progresso, E2E dos dois sistemas e CI dos novos SHAs. Histórico disponível na origem e homologação real devem ser medidos separadamente. Não houve deploy, pareamento, envio real, replay ou rotina de backup/dump/restore.

## Incremento de mídia e Minhas — 12/11

A intenção de mídia fixa Account, inbox, integração, identidade lógica, instância, revisão do destino, usuário e SHA256 do token original. Regenerar o token ou alterar destino não herda a autorização anterior. Objeto privado e descriptor são imutáveis; replay pode reparar o mesmo objeto, sem retargeting. O job de baixa prioridade lê por streaming limitado, confirma tamanho, SHA256 e MIME, cria o vínculo sem callbacks e somente depois emite PERSISTED com media_sha256. Redis/Sidekiq transporta o job; a obrigação ATTACH_PENDING fica no PostgreSQL e o scheduler recupera a lacuna COMMIT → enqueue. KEEP permanece.

As rotas multipart têm limite antes do parsing Rack (16 MiB + 64 KiB), inclusive variações de formato e barras. O contrato canônico usa JSON UTF8 padrão, com fixture compartilhada entre Ruby/JS. A carga de schema em banco vazio é testável por script/ci/jrc_history_schema_load.rb; o script é opt-in e aceita somente Rails test/banco sintético.

Minhas/Minhas e compartilhadas incluem histórico resolvido comprovado por recibo CHAT apenas nas inboxes em que o agente é membro e a política permite compartilhamento. Caixas exclusivas/URA permanecem restritas. O contador de revogação por inbox, a origem e a revisão do binding invalidam permissões de páginas retidas; mensagens novas por realtime não recebem prova histórica por dedução.

O E2E com journal PostgreSQL de origem, Broker, Rails HTTP, Redis/Sidekiq e MinIO passou em duas Accounts isoladas da mesma instalação Rails. Não representa duas instalações independentes nem uma sessão WhatsApp real. O host de origem operacional e os endpoints/painéis de progresso do Broker ainda dependem do fechamento da autoridade e composição; não habilitar captura produtiva a partir desta evidência.
