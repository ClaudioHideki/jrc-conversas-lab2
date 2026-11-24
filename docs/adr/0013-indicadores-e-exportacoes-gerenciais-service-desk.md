# 0013 — Indicadores e exportações gerenciais do Service Desk

**Estado** Aceita para implementação e validação locais.

O painel gerencial, a tabela e os quatro formatos usam a consulta autorizada do [ADR 0012](0012-relatorios-gerenciais-service-desk.md), incluindo o corte pela abertura original em 2026. O agrupamento por dia, semana, mês ou ano segue o fuso da conta e a data de referência selecionada. Os indicadores mantêm os totais da consulta quando o tamanho dos gráficos limita a quantidade de categorias ou períodos exibidos.

A taxa usa os chamados atualmente encerrados divididos pelo total filtrado. Resolvidos e cancelados são contados separadamente. O tempo de encerramento usa o último evento real de fechamento dos chamados atualmente encerrados. A primeira resposta e a resolução usam o último ciclo nativo do chamado. As médias só usam relógios concluídos com dados válidos. A cobertura informa quantos chamados ficaram sem medição.

As exportações gerenciais têm rotas e histórico próprios. Elas reutilizam o processamento em segundo plano e a auditoria do Service Desk. O worker revalida a autorização antes de gerar o arquivo, e o download verifica novamente o escopo. A rota pública genérica do armazenamento devolve 404 para os arquivos gerenciais. Os arquivos expiram em 24 horas.

O HTML é independente e permite refiltrar os dados exportados e baixar o CSV correspondente. O relatório não faz chamadas externas. Cópias baixadas passam a ser arquivos locais sob responsabilidade de quem exportou. Os limites são 5.000 chamados para HTML e 10.000 para os demais formatos por exportação. O PDF traz gráficos, indicadores e uma amostra de até 20 chamados. Os arquivos detalhados usam apenas as colunas do relatório.
