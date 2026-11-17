# Concorrência LIVE no workflow Flow/QR

O run main 44166609537 executou 211 exemplos no lote de módulos. Quatro
falharam com `Explicit disposable LIVE PostgreSQL runner required`: o glob
`spec/services/jrc_broker` incluiu `live_ingress_concurrency_spec.rb` no banco
`jrc_flow_modules_test`. O outro lote de efeitos de conversa passou. A mesma
suíte já falhava na main anterior (run 43994616555); a correção de MIME não
alterou a proteção nem esse arquivo de specs.

O workflow agora separa esse arquivo do glob genérico, como já faz com os
contratos de routing. Executa todos os quatro casos em um passo obrigatório
do lote de módulos, com banco `jrc_delivery_reliability_test`, pool 10 e
`JRC_LIVE_CONCURRENCY=1`. O próprio spec mantém a recusa para qualquer banco
ou ambiente diferente. O relatório JSON exige zero falhas, zero pendências
e pelo menos quatro exemplos. As suítes genérica e de routing permanecem.

Esta contribuição modifica apenas a configuração de CI. A imagem funcional
de áudio continua baseada em d3d6623254c48fc379fb9d54c14226a2e1e9c223.
Não exige migration ou alteração de runtime; o resultado remoto deve ser
registrado separadamente antes de promover este ajuste de CI à main.
