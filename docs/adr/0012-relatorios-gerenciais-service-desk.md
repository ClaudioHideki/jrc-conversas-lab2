# 0012 — Escopo e filtros dos relatórios gerenciais do Service Desk

**Estado** Aceita para a primeira etapa local de 24/11/2026.

O relatório gerencial é uma consulta de leitura na Central de Relatórios. As rotas operacionais existentes continuam atendendo seus próprios consumidores. A nova consulta usa a política de chamados e as regras de unidade, empresa e supervisão já usadas pelo Service Desk. O acesso gerencial exige administrador nativo com acesso ao módulo e à unidade. Para unidades sob supervisão restrita, a consulta também exige a concessão `reports_view` sobre a equipe e a fila.

A capacidade de consulta gerencial tem dependências explícitas das permissões do módulo e de chamados. Indicadores e exportação têm verificações próprias. A capacidade de exportação herda a restrição existente de `reports_export`. Os geradores gerenciais e a rota de exportação entram em uma etapa posterior.

O universo da consulta começa na abertura original de 1º de janeiro de 2026 no fuso de relatórios da conta. As datas de cadastro e atualização podem ser usadas como referência do filtro dentro desse universo. O dia final é inclusivo e o PostgreSQL usa o início do dia seguinte como limite exclusivo.

As origens nativas comprovadas são `manual` e `portal`. `legacy_import` é legado. Outros códigos entram como origens não classificadas até que haja uma regra explícita. A consulta preserva a origem armazenada e mantém chamados com relacionamentos opcionais vazios. Os filtros de pessoas, empresas e catálogo oferecem opções provenientes de chamados do escopo autorizado.
