# Release comum JRC — candidata 09/11/2026

O núcleo completo é o LAB2 Grupo JRC. CORE-REFERENCE.json registra a origem da candidata; o SHA final e os digests vêm da CI e do manifesto de publicação. O campo baselineSha não comprova a revisão instalada.

A Branef integra o núcleo sem retirar GLPI/intake. Sua extensão é descrita separadamente em EXTENSION-REFERENCE.json. O núcleo genérico não recebe a implementação GLPI. Bots/URA e conectividade genérica evoluem no Broker compartilhado; modelos, filas, agentes, contas, inboxes e credenciais permanecem por empresa.

Antes de promover: reconciliar refs e WIP, validar migrations (incluindo seus guards SQL), contratos de mensagens/mídia, permissões, isolamento, editor Flow e Compose efetivo. Exigir CI e testes de cada SHA final. Não usar a CI da baseline para aprovar o merge. Não enviar mensagens ou parear números como parte da publicação automática.

A release compreende imagens distintas Rails, Broker API/web e engine; uma empresa com extensão pode ter digest diferente usando o mesmo núcleo. Não substituir a imagem Branef pela imagem pura LAB2.

Status desta candidata: integração de código em andamento; ainda sem homologação operacional ou implantação. Backup/dump/restore estão fora deste incremento.
