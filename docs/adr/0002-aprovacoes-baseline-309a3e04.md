# 0002 — Baseline explícita da candidata de Aprovações

Estado: Aceita pelo usuário em 14/11/2026, exclusivamente para preparação e validação isoladas.

## Contexto
O gate anterior bloqueou o avanço concorrente da main histórica. A main 309a3e04f32ae1ca469fc202f6d1be0f9e50a20a já contém a Central e 24 commits adicionais. O usuário autorizou adotá-la sem reaplicar o layout e determinou interromper se main avançar novamente.

## Decisão
Produto fixado em 309a3e04; branch separada codex/central-aprovacoes-consolidada-20261114. Reutilizar somente evidências verificadas desse SHA, nunca as do produto anterior como prova da nova candidata. QA e infraestrutura ficam em branch isolada com checkout exato do produto. Preservar a limpeza de indicadores e os três testes concorrentes. Manter controle positivo de autenticação antes de testar a negativa Pundit 401 e comprovar o tema efetivo em cada captura.

## Consequências
O ledger de atualização contém 38 versões e preserva 13 sujeitos, incluindo as duas migrations de histórico. A guarda de recursos usa a versão auditada dessa main, com admissão adicional de 8 GiB efetivos e reservas de 750 MiB/750 MB. Nenhuma permissão ou regra funcional é alterada. A imagem anterior e as branches anteriores permanecem preservadas. Um smoke antigo de carregamento de bibliotecas não substitui a homologação Chrome nem os smokes completos de Rails/Sidekiq/PG/Redis/Scout/PDF/XLSX/OCR/assets.

Sem publicação, merge, deploy, backup, dump, restore, bancos reais ou build no Windows.
