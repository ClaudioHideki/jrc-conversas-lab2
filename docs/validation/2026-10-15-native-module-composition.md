# Composição candidata Flow/QR/ownership

O merge inicial reuniu66 paths de produto sobre JRC b58e093dd3a32fe97829a4566660b83ee48b9eca. O inventário final contém124 artefatos: produto, testes, configuração operacional, validadores e assets. Esse total não representa124 alterações de produto nem prova de instalação. O manifesto guard cobre85 arquivos e19 caminhos de admissão. Seus hashes finais devem ser gerados após o freeze com os blobs reais da base b58; arquivos novos têm baseSha256 null.

O input inclui o addon9, o Playbook resume já existente na base, nativeEditorBuild.js e os5 arquivos finais public/jrc-flow-editor. O editor foi gerado do Broker fc4ae8a1f3c940dc8ab2d1e369f3b658eab463a3, com sourceCommitted=true; o root registrou6 cenários de browser compilado aprovados. O manifesto de build próprio preserva o SHA, os inputs, outputs, notices e inspeção do bundle.

O laboratório do root exercitou64 exemplos na execução inicial e nos reruns focais:42 passaram inicialmente;9,10 e3 foram recuperados nos focais seguintes. Os logs correspondentes são native-modules-root-final.log, native-modules-red22-root.log, native-modules-red13-root.log e native-modules-red3-root.log no scratch coordenado do Broker. Não houve nova execução integral desses64 após a formatação. O ajuste final de fixture usa callback distinto e exige o índice jrc_flow_active_account_unique; esse exemplo passou isoladamente, e o CI candidato executará o conjunto consolidado.

Os testes observam callback/Bearer reais, PostgreSQL, locks concorrentes, intenção Message por ID antes do commit, POST fora da transação, revogação durante I/O e UNKNOWN durável. O status sent padrão de Message não confirma entrega: metadata/ledger permanecem queued até recibo delivered/read. Timeout e retry duplicado preservam a incerteza; o quiesce não apaga EXTERNAL DISPATCHED/OBSERVED/UNKNOWN.

O root aplicou3220 autocorreções seguras nos78 arquivos Ruby e verificou o lote final com parser e Layout/LineLength sem ocorrências. Os avisos restantes de métricas e lint não foram ocultados por configuração ou suppressions; RuboCop completo não foi declarado limpo. Observer9 e manifest3 tiveram12 testes Node aprovados antes da geração final dos hashes.

No freeze final, o inventário de121 artefatos foi gerado e verificado com os blobs reais da base b58, incluindo os assets do Broker fc4ae8a. Os12 testes Node do observador/manifesto passaram novamente; os20 fontes JSON/JS/Vue alterados e253 timestamps de migrations foram validados. ESLint dos dois componentes Flow e do cliente BFF encerrou sem erros. Textos novos usam o catálogo local en já existente, também utilizado pelos locales pt/pt_BR, sem editar traduções comunitárias.

Antes da primeira instalação/publicação, a CI do candidato b898 revelou que carregar o schema da base em20261012160000 marcava a migration candidata20261009180000 como aplicada sem criar suas tabelas. Somente esse arquivo novo foi renomeado para20261013140000_create_jrc_flow_native_registrations.rb; a classe e os bytes permaneceram idênticos (SHA-256 f3c2be944a8e78ba160a53eeb8188dc90524ee06d7bb674942fb92537e9ef598). O schema da base e as migrations antigas permanecem intactos. Trata-se de correção pré-release do candidato, não de renomeação de uma migration instalada. O inventário passa de121 para124 ao incluir o validador genérico, o helper puro de timestamps e seus testes; os manifestos aguardam o próximo freeze.

O helper observou RED com três falhas e GREEN de4/4 testes: recusa0918 e timestamps iguais à versão do schema da base, aceita131400 e falha se a versão base não puder ser lida. O validador consulta as migrations adicionadas no diff contra b58 e as novas ainda não rastreadas, e usa o schema original de b58 como autoridade. A CI Node executa essas regressões junto dos testes de observer/manifesto.

O bootstrap fresco terminou com exit0 no PostgreSQL local isolado `jrc_nico_broker_candidate_test`: carregou o schema original da base b58, aplicou as sete migrations candidatas e executou `db:abort_if_pending_migrations` sem pendências. A consulta final confirmou as dez tabelas candidatas, a coluna actor_id do ledger NICO e quatro triggers de configuração, fatos de envio e recibos imutáveis. Evidência local: `fresh-bootstrap-final.log`, resultado `{"fresh_bootstrap":"PASS","candidate_tables":10,"candidate_triggers":4}`. Nenhum banco ou serviço do servidor foi alterado.

A revisão focal acrescentou dois casos reais de Git R100: o destino de uma migration renomeada escapava do filtro de arquivos novos após stage/commit. O RED confirmou as duas falhas; `--no-renames` inclui o destino como novo e o GREEN terminou com6/6 regressões do validador,18/18 junto de observer/manifesto. A importação do compilador Vue ocorre somente para arquivos Vue, permitindo esses testes puros antes da instalação do pnpm. Os23 fontes alterados e253 timestamps passaram, com sete migrations posteriores ao schema da base; os dois manifestos foram regenerados e verificados após a correção.

O fechamento de layout/metadados não alterou o runtime NICO. QR, NICO, BFF e addon conservaram os hunks coordenados dos seus responsáveis; não foi introduzido outro motor. Os19 caminhos descrevem somente Flow, mensagem/attachment, atribuição/status, webhook, AgentBot e API legados implementados. E-mail/transcript mantêm o comportamento existente e ficam fora dessa prova; não se afirma cobertura de toda AutomationRule.

A CI flow-broker-candidate executa NativeResponders, exige pelo menos64 exemplos no lote de módulos e38 no addon, recusa failures/pending, executa observer/manifest e verifica os manifestos gerados. A conclusão operacional exige CI no commit candidato e observação real do host/worker/imagem: heartbeat por PID, desafio RO separado e assinatura exclusiva do observador externo com chave privada fora do app/Git. Não foi publicada uma attestation instalada nem verificado um deploy neste fechamento.

## Disponibilizar os módulos no candidato

Configurar igualmente no Environment de Rails e de todos os Sidekiq candidatos, além das origens/chaves privadas da integração Broker:

```dotenv
JRC_BROKER_ENABLED=true
JRC_FLOWS_ENABLED=true
JRC_FLOWS_EXTERNAL_BETA=true
```

As variáveis disponibilizam os recursos da instalação. Habilitar também as features da Account escolhida, no terminal Rails candidato, preservando suas demais flags:

```sh
bundle exec rails runner 'a = Account.find(3); a.with_lock { a.enable_features("jrc_broker", "jrc_flows"); a.save! }; puts "Módulos habilitados na Account #{a.id}"'
```

Substituir 3 pelo ID existente desejado. Esse comando não configura credenciais, não conecta WhatsApp, não publica fluxo e não habilita NICO. A configuração NICO por Account está no [guia NICO/Broker](2026-10-15-nico-broker-coordenado.md). Usuários e permissões continuam no JRC; o operador precisa de acesso atual às caixas selecionadas.

Após migrar o banco e reiniciar Rails/Sidekiq com a mesma imagem, usar **Conexões WhatsApp / QR** para conectar o número e **Flows → Flow do Broker** para registrar a integração da Account e abrir o editor compartilhado. A configuração inicial é administrativa; o editor recebe somente a sessão delegada e as caixas autorizadas. Registro, autorização de renovação e verificação dos executores são etapas distintas; uma conexão HTTP disponível não concede autoridade ao bot. O [procedimento do observador externo](../../deploy/jrc/OWNERSHIP-OBSERVER.md) entrega os comandos e os pins necessários para verificar o candidato instalado. Nenhuma dessas etapas foi executada na produção por este desenvolvimento.
