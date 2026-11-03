# Recuperação de campanhas — relógio determinístico da suíte

O lote Rails de 272 exemplos teve 22 falhas de recuperação concentradas em uma janela curta. A preparação usava o horário real com janela UTC `00:00`–`23:59`, enquanto as expectativas exigiam criar a mensagem imediatamente.

A reprodução controlada em PostgreSQL descartável, às `2026-11-02T23:59:30Z`, confirmou a causa: aprovação válida, delivery `sending`, nenhuma mensagem criada e próximo horário `2026-11-03T00:00:00Z`. O exemplo que esperava `account.messages.sole` falhou. Evidência: `output/specs-20261102/campaign-clock-boundary-red.log`, no workspace de execução. A primeira tentativa apontou outro banco de teste com migrations pendentes e foi corrigida antes dessa reprodução; não foi executada contra produção.

Correção apenas em `spec/services/jrc_campaigns/broker_recovery_spec.rb`: a preparação congela o relógio em meio-dia UTC e o libera no ensure. Os exemplos de limites de janela continuam a alterar o horário explicitamente. Não houve alteração na regra de agendamento, aprovação ou envio da aplicação.

Resultado posterior: **55/55 exemplos de recuperação aprovados** no lote real Rails/PostgreSQL de 116 exemplos. Esse lote também contém novos RED de outros incrementos; seu resultado global não é integralmente verde. Evidências: `lab2-historical-adapters-red.log/.json` no diretório de execução acima. Testes de campanhas usam portas HTTP sintéticas e não enviam mensagens a números reais.

Esse resultado confirma a regressão automatizada de recuperação, inclusive a preservação de mensagem/anexo e UUID do callback. Não comprova entrega em WhatsApp produtivo nem elimina a necessidade de CI no novo SHA e homologação operacional autorizada.
