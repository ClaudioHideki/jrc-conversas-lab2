# Atualizações remotas integradas à candidata completa — 13/11/2026

## Origem e preservação

Pedido do usuário: verificar atualizações no GitHub LAB2, consolidar com o trabalho existente e gerar/publicar a imagem para o servidor. Destino: branch isolada `codex/whatsapp-history-order-20261111`, base limpa `6ca6c6cd6f6a2fcce78a709226f159fcaf9b4ce0`. Main remota ainda `d8a83b824b11cc68ddbbce7c79681f368051fb70`; nenhuma main alterada.

Foram comparadas 90 referências locais após buscar todas as branches publicadas. Isso inclui referências históricas já preservadas. As branches CI de 13/11 não mudam código funcional, schema, imagem de runtime ou dependências: são wrappers específicos de validação/publicação do produto anterior `56407939`. Não sobrescrever o workflow atual ou usar a CI desse produto antigo para aprovar esta imagem.

A PR #8 termina em `549102e44a0141d088e88551cb552d1157c17076`. Git patch equivalence confirmou que `1ea6e57c`, `56be4fbf` e `1f275446` já estavam incorporados. Os incrementos `a822141b` e `549102e4` faltavam; o merge da branch preserva o histórico dos cinco commits sem duplicar seu comportamento. A simulação e o merge real não apresentaram conflitos. Não há configuração ou payload de cliente nessa integração, apesar do nome histórico da branch citar Precimech.

## Alteração efetiva

Seis caminhos importados mudam: `MessageError.vue`, seu spec, `en/chatlist.json`, `Whatsapp::RetryPolicy` e dois request specs de retry. Permitem uma tentativa manual rastreável para rejeições Meta 130472/131049/131026 e cabeçalho fixo de texto em template aprovado. Os controles existentes continuam obrigatórios: usuário autorizado, Account/inbox, mensagem original falha e pública, template permitido e parâmetros completos, cooldown e uma tentativa persistida por original. A tentativa original e seus recibos são preservados. UNKNOWN não vira autorização de novo POST. A Meta pode rejeitar novamente.

O transporte e upload de mídia protegida de `WhatsappCloudService`, todo o histórico Broker/JRC, grupos, Minhas, permissões, políticas de supervisão/URA, schema, migrations, locks e runtime da base foram preservados. Nenhuma atualização ou imagem nova do Broker é necessária por causa desse delta do LAB2.

## Reprodução e contratos

Antes do merge, a cópia temporária exata da suíte nova encontrou 6 falhas/10 testes aprovados no componente antigo; depois do merge, 16/16 aprovados. O arquivo temporário foi comparado com o spec integrado e removido; o spec upstream permanece no caminho original.

O guard estrito de runtime inicialmente recusou as quatro diferenças novas em `app/`. Foram admitidos apenas os hashes SHA-256 canônicos exatos desses arquivos, com o commit de origem registrado na saída do contrato. Preservados pins, locks, stage final da imagem, schema LF, lista de migrations e o bloqueio de qualquer outro arquivo funcional. Nove testes de contrato cobrem o lock revisado e a rejeição de adulteração/ausência dos arquivos novos; o workflow de identidades executa esses testes explicitamente.

## Revisão e correção adicional

A revisão independente identificou um P2 de feedback: a nova interface retirava `meta.error`, enquanto a ação do store grava nesse campo a justificativa da negativa do backend. Não havia toast nesse caminho. A perda foi reproduzida em dois testes RED: negativa junto ao erro original e negativa sem erro do provedor. A correção mantém ambos no tooltip existente, sem acrescentar parágrafo à conversa, sem mexer em envio ou estados. Metadados legados nulos continuam aceitos. Regressão final: 74 testes/3 arquivos aprovados, incluindo 18 casos do componente. Os dois hashes alterados por esse overlay são pinados no guard; não se declara identidade integral com o arquivo upstream nesses dois caminhos.

Lint frontend final sem erros/avisos nos arquivos afetados. A primeira tentativa tinha apenas CRLF inserido pelo checkout Windows (244 apontamentos); normalizado para LF. Um apontamento posterior de quebra de linha no spec foi corrigido. Os 35 testes de migrations passaram; a primeira execução restrita teve dois erros de `spawnSync git EPERM`, e a mesma suíte fora da restrição de spawn passou integralmente. Actionlint 1.7.12 com checksum conferido aprovou o YAML em container local sem rede; ShellCheck integral cabe ao runner CI. Nenhuma dessas falhas intermediárias foi tratada como aprovação.

## Gates da entrega

Antes da publicação: lint dos arquivos afetados, Vitest de retry e regressões preservadas, testes de runtime/heap/migrations, revisão independente do delta, CI A–G e conexões no SHA novo. A imagem completa deve ser construída e aprovada pelo smoke Alpine antes do push GHCR. O digest e o artefato finais serão registrados no checkpoint externo pós-publicação; o texto deste commit não pode conter seu próprio SHA futuro.

As evidências de 6ca6 são históricas, não aprovação automática desta candidata. Nenhum envio, conexão de número real, replay de UNKNOWN, migration produtiva, dump, backup ou restore faz parte dessa consolidação. A implantação final depende de conferir o estado real do Dokploy e da autorização já recebida, sem presumir acesso funcional ou versão ativa.
