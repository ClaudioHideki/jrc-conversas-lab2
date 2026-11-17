# 0006 — Alinhamento verificado de MIME Ogg/Opus do Broker

Data: 17/11/2026. Status: implementado em candidata, aguardando GREEN e release.

O arquivo sintético Opus real foi identificado como audio/opus por Marcel.
O Broker usa audio/ogg para o container. O receiver comparava os rótulos
literalmente e recusava os mesmos bytes/hash com JRC_LIVE_MEDIA_INTEGRITY.
Leitura produtiva reproduziu a diferença sem gravação. O RED em
44154858796, SHA4e90ea11, aprovou74/75 exemplos nativos e falhou somente no
novo arquivo Opus com HTTP409 em vez de200. Interface passou; testes após
a etapa RED não executaram e não são declarados aprovados.

Decisão: compartilhar entre LIVE/histórico um normalizador estrito que
aceita a equivalência audio/opus detectado → audio/ogg declarado somente
com cabeçalho Ogg BOS/OpusHead completo, versão1, mono/stereo e mapping0.
Os descritores, hashes, bytes, IDs, assinaturas, escopos e recibos permanecem
imutáveis. Não habilita formatos arbitrários nem trata octet-stream como áudio.

Base da candidata: runtime688626104ca89001a74da142d121610509254025,
reconciliado com main89779191 por merge e280bb05. Preserva os incrementos
de chamados, projetos e encerramento já instalados. Nenhuma migration,
alteração de retenção, sessão, grupo, bot ou credencial. Complementa o
reparo outbound restrito no Broker; não substitui aceite físico bidirecional.
