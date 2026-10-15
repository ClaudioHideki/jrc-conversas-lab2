# Observação externa do candidato

Este diretório entrega o produtor e a configuração operacional. Não contém uma prova instalada. A capacidade exige observar a imagem publicada e os processos em execução; os testes com driver sintético não substituem essa etapa. A prova dos 19 caminhos cobre JrcFlows/Playbook e os executores implementados de mensagem/attachment, atribuição/status, webhook, AgentBot e API legados. As ações de e-mail/transcript mantêm o comportamento existente e ficam fora dessa prova; não se afirma cobertura de toda AutomationRule.

## Artefato e relógios

Rails e todos os serviços Sidekiq devem executar a mesma imagem candidata fixada por digest. A imagem precisa conter `.git_sha` e o label OCI `org.opencontainers.image.revision` iguais ao commit publicado. O Docker precisa apresentar esse digest em `RepoDigests`; uma tag ou um digest copiado para ENV não é prova. O manifesto guard é gerado a partir dos payloads Git com LF, e `baseSha256` usa o blob Git real de b58, inclusive schedules que já existiam. Em um checkout Linux do commit candidato:

```sh
node script/jrc_native_module_manifest.mjs --check
node --test deploy/jrc/ownership-observer.test.mjs
```

O observador usa o Docker do host. A aplicação não recebe o socket Docker nem a chave privada. O app inicia antes da primeira attestation: initializers registram hooks e iniciam heartbeat; aquisição/capabilities aguardam a evidência válida. Heartbeat é medição por PID, não assinatura. Ele usa `clock_timestamp()` e prova nonce, PID namespace, start ticks, hashes e ancestors carregados. Puma registra cada PID após fork; o probe exclui o master quando encontra cluster workers. O observador compara cada processo com `/proc` e a imagem do Docker, reconsulta a geração dos containers, e só então assina Ed25519. SQL e host com relógio adiantado/atrasado falham fechados; corrigir sincronização operacional, sem ampliar TTL para mascarar drift.

## Preparação no host candidato

Os comandos a seguir são para o host de testes autorizado, depois de verificar commit, digest e artefato de CI. Não foram executados em servidor por este pacote.

```sh
install -d -m 0755 /opt/jrc-ownership-observer /etc/jrc-ownership-observer
install -d -m 0700 /var/lib/jrc-ownership-observer/private
install -d -m 0755 /var/lib/jrc-ownership-observer/public/challenge /var/lib/jrc-ownership-observer/public/attestation
openssl genpkey -algorithm ED25519 -out /var/lib/jrc-ownership-observer/private/signing-key.pem
chmod 0600 /var/lib/jrc-ownership-observer/private/signing-key.pem
install -m 0644 deploy/jrc/ownership-observer.mjs /opt/jrc-ownership-observer/ownership-observer.mjs
install -m 0644 config/jrc_flow_ownership_guards.json /etc/jrc-ownership-observer/jrc_flow_ownership_guards.json
install -m 0600 deploy/jrc/ownership-observer.example.json /etc/jrc-ownership-observer/observer.json
```

Preencher `observer.json` com o Compose project real, todos os serviços Rails/workers e a quantidade mínima de réplicas. Enumerar explicitamente somente infraestrutura em `ignoredServices`. Qualquer serviço de aplicação desconhecido, worker parado, one-off ativo ou réplica ausente impede assinatura. Preencher o repositório, digest publicado e SHA revisado; os placeholders do exemplo são recusados. Conferir os caminhos `/usr/bin/node` e Docker CLI no host antes de instalar a unit.

Adicionar `compose.ownership-observer.yml` ao Compose do candidato com `JRC_OWNERSHIP_STATE_DIR=/var/lib/jrc-ownership-observer/public`. Challenge e attestation são bind mounts separados, somente leitura, em Rails e Sidekiq. Heartbeats ficam em `/tmp` gravável próprio de cada container. Nunca montar o diretório privado no app. Não compartilhar esse estado com outro projeto/host.

```sh
node /opt/jrc-ownership-observer/ownership-observer.mjs --config /etc/jrc-ownership-observer/observer.json --check
node /opt/jrc-ownership-observer/ownership-observer.mjs --config /etc/jrc-ownership-observer/observer.json
```

`--check` mede os processos reais sem assinar. Um resultado publicado contém somente source, digest, quantidade de processos e expiração, sem chave. A falha remove a attestation anterior; se o observador cair abruptamente, a expiração SQL ainda fecha a aquisição. Para renovar automaticamente no host candidato, instalar as duas units e habilitar o timer. A cada atualização de imagem/source/guard, atualizar os pins revisados no arquivo externo antes de renovar. Rotação de chave requer substituir a chave pública por procedimento explícito; o produtor recusa sobrescrever uma pública divergente.

## Aceitação operacional

Registrar o SHA e digest realmente observados, hash do guard de CI, saída verificada/publicada, PIDs de Rails e todos os workers, e expiração. Confirmar mounts RO e ausência de Docker socket/private key no app. Reiniciar uma réplica e verificar que a evidência anterior deixa de ser aceita até o novo PID responder ao desafio; parar um worker ou adulterar um payload deve remover/expirar a evidência. Um nonce antigo no canal RW não substitui o desafio RO. Esse registro é separado de build, publicação de imagem e deployment; nenhum deles implica os outros.
