# JRC Conversas - Cadastro Mestre sobre a base oficial 80f7305

**CANDIDATO DE CODIGO-FONTE. HOMOLOGACAO NATIVA PENDENTE.**
Data da entrega: 02/10/2026.

Este projeto completo parte EXCLUSIVAMENTE de `JRC-CONVERSAS-ULTIMA-ATUALIZACAO-80f7305-20261002.zip`.
O candidato antigo foi referencia de alteracoes revisadas; nao foi copiado sobre o projeto atual.
Service Desk, Projetos, Minha Agenda, CRM comercial, Conversas, Campanhas, Telefonia, NICO e Flows foram mantidos.
Nao foi executado deploy, build Docker, alteracao de banco do usuario ou push Git.

## Antes de usar

Extraia em uma pasta NOVA. Nao substitua uma instalacao em execucao sem comparar a revisao implantada, fazer backup e homologar.
A feature `jrc_customer_master` permanece DESLIGADA por padrao e sua ativacao e por Account.
As tres migrations novas devem rodar apenas no banco de teste/laboratorio primeiro. As migrations antigas e schema.rb foram preservados.
Nao use o candidato anterior nem suas instrucoes de ativacao como base para esta entrega.

## Ordem de leitura

- `docs/jrc_customer_master/01-AUDITORIA-DIFERENCIAL-PREVIA.md`: auditoria feita antes do porte.
- `docs/jrc_customer_master/03-ARQUITETURA-E-ESCOPO.md`: implementacao e limites reais.
- `docs/jrc_customer_master/04-HOMOLOGACAO-E-ATIVACAO.md`: preparacao, testes, revisao de dados e ativacao.
- `docs/jrc_customer_master/05-TESTES-E-LIMITACOES.md`: evidencias locais e falhas reproduzidas na base intacta.
- `docs/jrc_customer_master/06-API-E-VINCULOS.md`: endpoints e campos de integracao.
- `docs/jrc_customer_master/07-PORTABILIDADE.json`: manifesto do porte de codigo.

## Atencoes importantes

Minha Agenda continua declarando `native_tasks_not_available` para tarefas Service Desk. Nao foi inventada uma fonte de tarefas.
Contratos comerciais EXISTEM no CRM desta base e foram incluidos no Customer360. A tela de Contratos do Service Desk continua planejada, como na fonte.
Tres suites Ruby antigas continuam com as mesmas falhas/erros da base oficial intacta. Isso exige revisao na homologacao; nao equivale a uma suite completamente verde.
Rails, migrations, PostgreSQL, compilacao Vue, HTTP, browser e PABX nao foram homologados neste ambiente.

A desativacao da feature conserva todos os dados e o novo schema. Nao execute rollback/drop para desfazer a interface.
