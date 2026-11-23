# Origem nativa das automações de encerramento

Estado: incremento candidato; execução nativa e aceite do executor ainda pendentes.

O editor de configuração foi validado em `8f362263` e na CI `45237591913`. Configurar uma regra enquanto o executor está indisponível não autoriza disparar retroativamente os atendimentos existentes.

O próximo incremento registra a origem real do evento nativo de tabulação e a conclusão efetiva do ACW em tabelas privadas e imutáveis. Reutiliza o início de chamada já fixado pelo banco e as versões existentes do catálogo, da regra e do escopo da fila. Não duplica o catálogo de contatos, o início de chamada, o cadastro de projetos ou o fluxo nativo de tabulação.

A migration é prospectiva: registros anteriores mantêm os dois novos campos de evidência da perna nulos. Não reconstrói eventos, não ativa regras, não cria concessões e não dispara destinos. A confirmação antecipada do motivo permanece distinta da conclusão do ACW. Dados livres do formulário e observações não fazem parte dessas evidências.

A futura execução deverá exigir autorização atual do agente original e da unidade/fila de origem em cada tentativa, além da autorização nativa do destino. Uma evidência registrada não é uma concessão. Versões antigas sem autorização explícita de execução continuarão sem poder gerar efeitos. Desativar uma regra deve bloquear também suas pendências antigas; reativar não as libera.

O limite transacional do futuro worker usa `Account FOR NO KEY UPDATE`, sem substituir a transação de autorização existente. Isso preserva a serialização das mudanças de autoridade e permite a verificação `KEY SHARE` das FKs nativas dos destinos. Quatro testes com conexões PostgreSQL independentes devem comprovar a compatibilidade; não presumir que a análise do lock prova a execução correta dos destinos.

O aceite exige instalação nova, atualização populada sem backfill, reexecução, recarga do schema, FKs e triggers exatos, privacidade dos binds SQL, invariância das versões e concorrência real. Os testes históricos mantêm suas asserções; somente seus helpers de DDL transacional removem temporariamente as novas dependências durante o teste, com rollback. Nenhuma FK de produção é removida.

Recibos por destino, efeito e recibo na mesma transação, idempotência, falha parcial e reprocessamento ainda pertencem aos próximos incrementos. O presente registro não conclui F10-A/F10-B, a figura 10 ou a Parte 1. O contrato e os comandos reais do PABX continuam fora do escopo.
