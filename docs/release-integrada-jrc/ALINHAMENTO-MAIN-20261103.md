# Alinhamento da main — 03/11/2026

O usuário autorizou integrar as versões consolidadas dos dois produtos na main. As candidatas foram promovidas por fast-forward, preservando commits, branches, imagens imutáveis e alterações locais de outros trabalhos. Não houve force push, reset, deploy, migration produtiva ou novo envio neste incremento.

- Broker: main avançou de `ea7dc741d0c63792a969dddeac2bd35b6cbdf514` para `c0cd026e3d0e87ece7c7a5aa036e70c1b0f7ad37`, incluindo os dez commits da candidata e a correção JPEG com legenda. CI da main `41715520817`: sucesso.
- JRC Conversas: main avançou de `5f619b7cb3f922ead95613200afe5cb476694952` para `a30fb50e6e53f1bc9eebe66ce50d13e46820b1c8`, incluindo 81 commits consolidados. Os quatro incrementos de 26/10 têm equivalentes já incorporados; não foram duplicados. O commit documental a30fb50e preserva os arquivos executáveis da imagem edd6f1a2 já implantada.

## Correções encontradas nas verificações da main

1. Flow: a CI `41715610373` rejeitou o manifesto de ownership antigo. Dez hashes de guardas e outros itens do inventário não acompanhavam os fontes consolidados. Os dois manifestos foram regenerados pelo gerador existente, mantendo os 90 guardas, 180 artefatos, a base histórica e as verificações negativas. Não houve modificação em app, lib ou migrations para contornar a validação.
2. NICO: a CI `41715610330` teve 21 falhas na limpeza das fixtures, porque os novos triggers append-only bloqueavam TRUNCATE. Somente os dois specs de concorrência foram corrigidos: a limpeza usa o bloco padrão do adapter Rails para suspender/restaurar triggers, exclusivamente após os guardas existentes de Rails test, banco descartável explicitamente permitido e opt-in. Um exemplo novo verifica que TRUNCATE continua proibido durante o teste. Nenhum trigger produtivo ou migration foi alterado.
3. CI: a regressão consolidada passa a verificar o manifesto antes do Rails, também é acionada por push na main, e o workflow de imagem exige na main os mesmos gates nativos e validação do SHA/branch já exigidos para a candidata. O workflow continua manual para publicar imagens.

## Evidências locais do ajuste

- RED do gate de manifesto ausente, seguido de GREEN.
- RED do gate de release ausente na main, seguido de GREEN.
- 24 testes Node: aprovados, zero falhas, incluindo manifestos, observador, timestamps e release gates.
- Verificação dos hashes atuais: 90 guardas e 180 artefatos, zero divergências.
- Rails/PostgreSQL real isolado: 43 exemplos, zero falhas; inclui concorrência NICO, entrega incerta, restauração dos triggers e histórico imutável.
- A primeira preparação local apontou SCHEMA para um arquivo temporário inexistente e foi corrigida. A primeira rodada no disco do laboratório excedeu statement_timeout na limpeza; foi interrompida para diagnóstico. A rodada final usou banco exclusivo em armazenamento temporário de memória, com os mesmos timeouts. Isso não é teste de durabilidade ou benchmark de produção.
- O ajuste não modifica código executável em app, db ou lib, nem introduz migrations. Os manifestos de config são metadados de integridade atualizados; sua presença na main não implica novo deploy.

As novas execuções de CI do SHA do ajuste devem ser consultadas separadamente. As execuções antigas com falha permanecem como evidência da regressão detectada, sem serem anunciadas como aprovadas.

O primeiro run do novo gate também comprovou que o job de integração usava checkout raso e não possuía a base Git histórica exigida pelo gerador. O checkout desse job foi ajustado para `fetch-depth: 0`; a regressão do gate exige essa configuração. A validação não gera manifestos durante a CI e continua recusando base ausente ou hashes divergentes.

No SHA b857d277, Flow/QR e o job Broker/distribuição ficaram aprovados. NICO executou 235 exemplos com zero falhas, mas o RuboCop final apontou uma única indentação em `app/services/jrc_customers/visibility.rb`. A chamada encadeada foi alinhada, sem alterar sua lógica; o resultado de lint e a comparação da AST Ruby são registrados separadamente. As execuções de CI de cada novo SHA continuam distintas.

## Limites preservados

Branches históricas e específicas de outros ambientes, incluindo Precimech, não foram sobrepostas à candidata atual. PRs com base em branches antigas podem permanecer abertas mesmo quando seus commits já são ancestrais da main. Nenhuma pendência funcional previamente documentada de engine, custódia, capacidade ou integração externa foi declarada concluída por esta promoção.

Backup, dump e restore não foram executados. Produção continua nas imagens publicadas e verificadas anteriormente. As evidências operacionais do alinhamento ficam em `output/github-main-alignment-20261103/` no workspace principal.
