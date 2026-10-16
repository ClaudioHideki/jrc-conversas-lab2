# P3 — revisão atômica e protocolo de efeitos v2

Estado: addon protocolo2 validado em Rails/PostgreSQL reais em 15/10/2026: **38 exemplos, zero falhas**. RuboCop dos13 arquivos de produto/teste: nenhum apontamento. A integração Broker/BFF e o candidato externo continuam em execução; nenhuma implantação foi realizada.

## Fronteira de controle

A implementação aprovada usa `conversations.jrc_effect_control_revision`, incrementada na mesma transação por triggers PostgreSQL. Escritas de controle/destino de Conversation, mensagens outgoing de User públicas e privadas, external_echo e mudanças de roteamento de Contact/ContactInbox/Inbox participam da mesma trava da linha Conversation. Metadata NICO/Flow não cria exceção. `update_column` e `update_all` continuam cobertos.

As ações próprias também incrementam a revisão. O recibo guarda a revisão anterior e posterior, identificando o fato confirmado. A leitura posterior desse recibo não autoriza novo efeito com a revisão antiga. A revisão não é derivada de `updated_at`, nem de um hash do estado corrente.

O addon trava Conversation antes de validar a revisão e mantém a trava até gravar efeito e recibo. Não adquire trava bloqueante de Contact/ContactInbox após Conversation. Os triggers de roteamento podem adquirir Contact/ContactInbox antes de Conversation; leituras MVCC do addon sob a trava de Conversation observam a rota anterior enquanto a alteração concorrente aguarda. Após o commit da alteração, a revisão avança e impede continuação baseada no snapshot anterior. Nenhuma chamada HTTP ocorre nessa transação.

## Contrato

Account autenticada por token API de User ativo, confirmado e administrador. O ator vem do token; um campo submetido não prova identidade. A autorização é revalidada sob travas na transação. Context e recibo incluem `contact_inbox_id` e `routing_source_hash` (SHA256 de source_id), sem expor o endereço. O hash de requisição permanece o material multiplataforma aprovado no desenho Broker; a revisão esperada cobre a mutação desses pins.

- `GET jrc_flow_effects/capabilities?inbox_id=...`
- `GET conversations/:display_id/jrc_flow_effects/context`
- `POST conversations/:display_id/jrc_flow_effects`
- `GET conversations/:display_id/jrc_flow_effects/:operation_id`

Protocolo `jrc-conversation-effects/2`, operações `tag`, `attribute`, `note`, `resolve`. Etiqueta adiciona uma ocorrência; atributo faz merge de uma chave validada; nota usa MessageBuilder privado; resolver grava resolved explícito. A semântica terminal do nó é responsabilidade do motor Broker e exige este recibo confirmado antes de encerrar o ciclo.

Recibo único por Account/organização/operação, imutável no banco. Inclui escopo, ator autenticado, operação, hashes da requisição e prova, revisions anterior/posterior, resource revision e Message ID quando aplicável. Não guarda texto da nota nem prova bruta. Replay exige mesma identidade/conteúdo/prova e retorna o fato anterior; divergência é conflito. A mutação é revertida se o recibo não puder ser gravado.

## Laboratório e evidência

Volume exclusivo `jrc-effects-source-20261015`, banco descartável `jrc_flow_effects_test`, Redis /13 na stack Rails sintética compartilhada. O bootstrap inicial foi interrompido para serializar os processos Rails pesados; source/volume/banco foram preservados. O contêiner específico de bootstrap foi parado após confirmar que o Ctrl-C no cliente não havia encerrado o daemon.

RED inicial:30 exemplos,29 falhas; a leitura histórica sem mudança já passava. As falhas semânticas incluíram epoch ausente para SQL direto/Message/roteamento, rotas404 e classe de hash ausente. Uma falha era a fixture NICO usando classe de acesso incorreta, corrigida sem alterar a implementação NICO.

Primeira implementação:36 exemplos,6 falhas. Quatro eram ajustes nos testes concorrentes/HTTP; duas provaram defeitos reais: `Message.store` persiste content_attributes como string JSON, enquanto SQL pode gravar objeto, e Inbox.channel_id ainda não incrementava o epoch. A migration passou a reconhecer ambos os formatos e incluir a troca de canal/Account/tipo da Inbox. O teste SQL de JSON objeto e a separação de responsabilidade do teste de recibo levaram o total a38.

GREEN final: `bundle exec rspec spec/services/jrc_flow_effects spec/requests/jrc_flow_effects_spec.rb --format progress`,38 exemplos/0 falhas em64,33s (carga18,65s). Migration20261015150000 reaplicada somente no banco descartável próprio para conferir os novos triggers. RuboCop focal:13 arquivos,0 apontamentos.

Cobertura: controle sem callbacks, Message pública/privada/NICO e external_echo, Contact/ContactInbox/Inbox, atributos/etiquetas, rollback, quatro ações, revisão/ator/escopo/prova, cinco hashes Node/Ruby, imutabilidade SQL, ACK perdido, crash antes do recibo, duas conexões com bloqueio comprovado em pg_stat_activity, retry simultâneo com uma Message e fonte de destinatário alterada enquanto o efeito detém Conversation. A política existente de novo inbound após resolve é preservada; replay histórico não resolve novamente a conversa reaberta.

Não há HTTP no caminho transacional do addon. O root integra esses paths ao manifesto/installer e executa CI separado do ledger NICO, porque os testes concorrentes usam limpeza exclusiva de banco. A paleta Broker permanece indisponível até os gates funcionais restantes.
