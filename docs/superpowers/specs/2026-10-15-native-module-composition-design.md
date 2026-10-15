# Composição nativa para b58 + NICO e observação operacional

15/10/2026. Continuação autorizada do programa; branch candidata nos dois repositórios. Executar inline com TDD, sem agentes adicionais, commit/push, servidor/main ou suíte total. Root aprovou mapa, composição e desenho do observador. Durante a suíte Broker, arquivos novos Broker permanecem neste scratch.

## Referências e inventário

Base JRC: b58e093dd3a32fe97829a4566660b83ee48b9eca; checkout atual f8938d05846f556a81d6f2917347460eed288099 + NICO congelado do root. Fonte Flow: .sessions/p9-native-transport-candidate/installable-module-overlay/infra/modules/jrc-native-flow/source. Ownership: .sessions/p9-ownership-candidate/host/overlay. O p9-composition-map.md enumera os 33 novos Flow, 17 novos ownership, 5 merges Flow e 11 hooks. QR34 já equivalente é preservado byte a byte.

Preservar todos os corpos atuais de runner, dispatch, sidebar, routes e schedule; compor somente o delta. RecoveryJob Flow recebe apenas prepend após comunicação do patch ao root; seu módulo deve conservar o bloco b58 de recuperação do journal Playbook. Não editar NICO, Command, JrcBroker::Client ou RecoveryJob NICO. Enterprise deve ser pesquisado antes dos hooks.

## Playbook e drain

O webhook Playbook usa journal assinado existente. Claim e captura do request ficam em transação curta com os locks/fontes atuais. Depois do commit, checkpoint do guard, intenção de efeito independente e SafeFetch sem transação. Na volta, revalidar fontes/actor/owner/claim/node/journal em outra transação curta, registrar recibo e continuar pelo Runner atual. Alteração de autoridade no I/O impede continuação e conserva UNKNOWN; resultado incerto nunca autoriza repost.

O hook de transporte envolve o perform existente em OwnershipGuard por Account/Inbox e mede o POST em OwnershipEffects. Não criar runner, journal ou cliente HTTP concorrente. OwnershipQueues reconhece WebhookJob e PlaybookResumeJob. NativeOwnership inclui queued/dispatching/unknown do journal nas contagens; queued pode ser cancelado com journal válido após fence, dispatching/unknown nunca são apagados. O guard manifest continua com os onze caminhos mínimos do contrato e inclui os novos arquivos críticos no inventário.

## Observador externo

Apenas o observador de deploy possui a chave privada. Ele usa Docker CLI no host de operação para descobrir todos os containers do projeto configurado, exigir os serviços Rails/workers esperados e recusar serviços de aplicação não inventariados, parados, reiniciando ou de outra imagem. A imagem real vem de inspect/RepoDigests, a revisão de OCI e do artefato .git_sha. Pins revisados limitam o que se aceita; não são, sozinhos, a observação.

Cada processo Rails/Sidekiq escreve heartbeat com PID/startticks, nonce público do observador, hora SQL, guard manifest e hashes dos arquivos, confirmação dos ancestors/hooks carregados. O observador consulta /proc nos containers e cruza cada PID de aplicação vivo com o relatório; resposta de outro processo, nonce anterior, arquivo divergente, tempo futuro/stale ou worker ausente falha fechado. Só então assina payload curto compatível com OwnershipIdentity contendo Rails e todos os workers observados.

O runtime não tem Docker socket nem chave privada. Diretórios separados: challenge RO no runtime, heartbeat RW por container, atestação+chave pública RO. Diretório inteiro montado para receber rename atômico; não usar bind mount de um único arquivo que prende inode antigo. OwnershipIdentity aceita diretório operacional configurado e conserva config/guards dentro da imagem. Falha do observador revoga a atestação publicada; expiração é curta (<=300s), sem prova instalada baseada apenas em ENV.

Novos arquivos JRC planejados: app/services/jrc_flows/ownership_heartbeat.rb, config/initializers/jrc_flow_ownership_heartbeat.rb, script/jrc_flow_ownership_probe.rb, deploy/jrc/ownership-observer.mjs e configuração pública de exemplo/documentação. Pequeno config/puma.rb on_worker_boot cobre preload/fork; Sidekiq startup no initializer. Testes focais do produtor usam chave sintética fora do código; fixture Docker/proc é distinguido de observação real de imagem instalada.

## Distribuição

Gerador usa git cat-file dos blobs b58 reais para baseSha256, nunca snapshot parcial. Pacotes QR/Flow/ownership transportam somente arquivos whitelist do checkout composto, com hashes Linux LF e proveniência80f+b58; instalador verifica base exata ou payload já aplicado, rejeita drift/symlink e prepara fonte somente. QR é no-op verificado. O guard manifest é regenerado depois dos merges e antes dos manifests de pacote. Ativação, migrations, credenciais e flags não são executadas pelo instalador.

Editor comum será reconstruído somente após inputagent encerrar contratos e root liberar. Usar o React editor/backend Broker atuais; não manter outro motor/UI. Registrar inputs e hashes dos outputs e transportar assets ao JRC e pacote Flow.

## Evidência

RED/GREEN focal do webhook exige transaction_open? false no SafeFetch e revalidação após I/O. Gates de composição verificam preservação b58, QR idêntico, todos os hooks/manifest/base blobs e instalador em cópia completa. RSpec usa volume próprio clonado do Linux congelado e DB jrc_flow_modules_test, cache próprio, sem modificar jrc_nico_broker_test ou volume root. Observador precisa testes de ausência/stale/mismatch/nonce/processo e assinatura/expiração. Aceite de imagem instalada e deploy continuam explícitos, fora desta composição.

## Corte e evidência atual

O inventário versionado é deploy/jrc/module-composition-input.json; script/jrc_native_module_manifest.mjs lê os blobs Git b58 reais e gera guard + MODULE-COMPOSITION-MANIFEST.json. Os manifests são fonte/artefato, installedProof=false. QR preserva34bytes do checkout, inclusive o Client que recebeu mudanças NICO do root. Os assets React anteriores ainda aguardam o build atual sob responsabilidade do root em apps/web/src/native-flow e scripts/build-native-flow-editor.mjs; não tratar o bundle antigo como editor final.

RED webhook real observado em Rails/PG (2casos SafeFetch dentro de tx). Fonte refatorado; GREEN real pendente da janela coordenada. Identity teve2REDs semânticos e2GREEN puros (OpenSSL real, relógio SQL como fixture fixa, sem Rails/PG); a rodada Rails usa relógio SQL real. ObserverNode9/9 e manifestNode3/3 passados. Nenhuma attestation operacional foi publicada ou imagem declarada instalada. O incremento aprovado posterior estende guards/prova para AutomationRules/AgentBot e deve fechar a lacuna antes da capacidade ampla. Configuração operacional concreta: deploy/jrc/OWNERSHIP-OBSERVER.md e compose.ownership-observer.yml; chave privada somente externa.
