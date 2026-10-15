# Envio NICO — autoridade no commit e ledger durável

Desenho aprovado pelo coordenador em 15/10/2026 após revisão de fonte. Complementa o envio coordenado, sem alterar controllers, OperationalAccess global ou políticas Enterprise. Sem produção, commit ou push.

## Problemas comprovados

O worker relê permissões sob Command → operação → Conversation, mas essas leituras não bloqueiam AccountUser, CustomRole ou grants. Controllers existentes alteram/deletam essas linhas diretamente. Uma revogação pode confirmar depois da última leitura e antes da Message. O objeto User também não é recarregado nem consultado por active_for_authentication?; disponibilidade offline não representa revogação.

O recipient atual não fixa contact_inbox_id/source_id, embora transportes usem essa rota. Mudança de rota mantendo o mesmo Contact/Inbox deve invalidar a prévia.

Por fim, excluir o último vínculo AccountUser agenda a exclusão do User. FK user → sessão → Command e as novas FK command/user → operação em CASCADE apagam o ledger de uma intenção remota OPEN. A referência local precisa sobreviver a esses registros apagáveis.

## Gate local de commit

BrokerSendCommitGate roda dentro da transação já protegida pelo lease, imediatamente antes da criação. Bloqueia linhas efetivas com FOR SHARE NOWAIT em ordem determinística: Account, User, AccountUser, CustomRole, Inbox, grants InboxMember/TeamMember/ConversationParticipant, Binding, Contact e ContactInbox. A Conversation já está bloqueada pelo caller. Queries e avaliação de política são uncached após os locks; associações usadas são recarregadas. Não há HTTP nesse trecho.

O gate exige User existente/active_for_authentication?, Account ativa com NICO/integração habilitados, membership vigente e política ConversationPolicy atual, incluindo overlay Enterprise. Grants efetivos e CustomRole permanecem estáveis até commit. NOWAIT evita esperar sob a ordem Command/Conversation enquanto uma transação legada possui os locks na ordem oposta. Contenção retorna para reconciliação da mesma intenção, com takeover_id já conhecido; não cria mensagem ou nova pausa.

A política não é substituída por uma lista própria de permissões. Offline/busy continuam permitidos se a autorização vigente permite. A rota pinada inclui contact_inbox_id e source_id, além da identidade e campos de controle existentes, e é revalidada sob locks antes da Message.

O commit também compara os campos reais da Integration com a instância de Context que construiu o client antes do HTTP: origem, organização, Account, revisão de destino e ciphertext da credencial. A comparação fica apenas em memória, sem registrar credenciais/digests em recibos ou logs. A identidade completa do Binding local (id, Account, Inbox, integration_id e instance_id) é fixada na prévia e comparada depois dos locks. Mudança desses dados entre pausa e commit impede criar a Message.

JrcBrokerIntegration não possui state nem account_credential_version. O estado ativo e as flags pertencem à Account e são revalidados pelo Gate. O protocolo remoto NICO expõe credentialRevision, derivado de credential_version do Broker e fixado na solicitação/recibo da pausa; as tabelas de configurações nativas possuem outra account_credential_version. Este corte não cria uma coluna local para representar uma autoridade remota inexistente no contrato de Context.

## Ledger pertencente à Account

A migração candidata ainda não publicada passa a ter command/user opcionais com ON DELETE SET NULL. A associação Command nullifica a referência; excluir Command ou User não destrói a operação. actor_id é um identificador imutável do ator original, sem FK, usado somente pela API interna de contexto/cleanup. Nenhum FakeUser é criado.

message_created_at é gravado no mesmo commit da Message e nunca removido/alterado. Essa evidência não depende de a FK Message continuar existindo. Sem Command/User antes desse fato, o worker só pode cancelar/reconciliar a intenção com a credencial da Account e o actor_id capturado. Depois do fato, nunca pode criar outra Message ou afirmar que nada foi enviado. Message apagada ou sender nullificado exige HALTED/reconciliação manual quando a prova canônica não permite completar; a prova do Broker não será relaxada.

Claim e updates de recibo suportam Command ausente. O cancelamento continua invalidando o lease antes de HTTP; resposta atrasada não produz Message. COMPLETE/CANCELED não ativam bot. A Account e o destinatário continuam sendo os limites do ledger; excluir a Account remove seu conteúdo conforme o ciclo de vida existente.

## Verificação

Novo spec opt-in `JRC_NICO_GATE_CONCURRENCY=1` usa somente os nomes explícitos jrc_nico_gate_test (local) ou jrc_nico_broker_candidate_test (CI), com Rails test/PostgreSQL e nome real da conexão idêntico ao ambiente. Fixtures são committed; guard de ServiceDesk permanece igual. PostgreSQL real com duas conexões e barreiras verifica revogação antes do gate, locks do worker fazendo DELETE/role update aguardar commit, NOWAIT sem Message, leases/cancelamento, usuário desconfirmado versus offline, mudança de rota e exclusão User/Command/Message. RED deve ser observado no código anterior antes da implementação. Rodadas focais somente; evidência de 120 Rails/83 UI anterior não valida automaticamente esta mudança.

A rodada focal usa o volume NICO anterior mais os nove arquivos deste complemento. O initializer composto de OwnershipHooks exige o conjunto completo de dependências e não será copiado isoladamente. Boot e regressões da árvore composta final pertencem à validação integrada/CI.

## Corte de transporte e complemento de vínculo

O controle de QR e o takeover NICO usam resoluções distintas no Broker. NicoTakeovers/captureTakeover e ChatwootControlAuth são genéricos: resolvem connection/channel/conversation, permitem executor NONE ou BROKER com remote_binding_id null e não exigem BAILEYS/instance_id. O protocolo0062 existente atende BROKER_TRANSPORT e CENTRAL_TRANSPORT quando a Account possui a credencial de controle exigida; a credencial flow/outbound não herda esse escopo.

Um resolver JRC comum seleciona o vínculo QR ou o vínculo/registro nativo real da Account/Inbox. O registro nativo deve permanecer ACTIVE, sem revogação, com prazos válidos pelo relógio do banco e com revisão/target coerentes. Origem, organização e destino precisam corresponder ao Context da Account; channelId e account_credential_version precisam corresponder à snapshot NICO. Esses identificadores e versões são pinados na prévia e revalidados no commit sob locks. Nenhuma instância QR é inventada para CENTRAL. Vínculo nativo sem controle/registro válido é recusado explicitamente, inclusive pela ferramenta genérica. Expiração/revogação não abre fallback; os bindings persistem e podem representar FREEZE. Notas privadas e caixas sem vínculo conservam o contrato existente.

A identidade pinada da Inbox precisa incluir id, account_id, channel_type e channel_id. O lock da Inbox só estabiliza o valor atual; ele não prova que o transporte permaneceu igual à prévia. O vínculo QR precisa continuar apontando para uma Inbox Channel::Api da mesma Account. Regressões separadas cobrem a troca do canal após aprovação e um QR stale que passou a usar WebWidget.

O resolver usa o mesmo Context/credencial de controle por Account e o mesmo ledger0062, com leases, cancel-only e prova canônica de Message existentes. O Broker continua decidindo executor/fence/drain antes de PAUSED; JRC não converte DRAINING/UNKNOWN ou executor remoto incompatível em autorização de envio. O Gate bloqueia também as linhas nativas efetivas com SHARE NOWAIT. Nenhum endpoint ou motor novo é necessário. O corte não coordena ferramentas de status/time/responsável nem libera automaticamente ownership scopes em FREEZE.
