# Homologacao - Estrutura Organizacional CRM

## Pre-requisitos

1. Backup do banco do laboratorio.
2. Usar Ruby/Node/PostgreSQL compativeis com o projeto.
3. Executar as migrations pendentes em ambiente de laboratorio.
4. Nao ativar a restricao organizacional antes de cadastrar/revisar empresas, unidades, equipes e escopos.

## Roteiro funcional

1. Abrir `CRM -> Configuracoes -> Estrutura Organizacional`.
2. Definir o nome organizacional do Grupo.
3. Criar duas ou mais Empresas internas e confirmar que aparecem no Cadastro Mestre como `Interno`.
4. Criar unidades vinculadas a empresas diferentes.
5. Confirmar que unidades legadas eventualmente existentes sem empresa continuam visiveis e nao foram migradas automaticamente.
6. Criar/reutilizar equipes nativas para Financeiro, Backoffice, Suporte e Comercial.
7. Adicionar/remover membros e validar que os mesmos Team/TeamMember sao vistos nas configuracoes nativas.
8. Definir um departamento com escopo `Grupo` e outro com escopo `Empresa`.
9. Tentar atribuir a um membro um escopo fora da abrangencia da equipe; a API deve rejeitar com 422.
10. Atribuir escopo menor e valido ao mesmo membro; deve salvar.
11. Tentar desativar empresa/unidade com abrangencias ativas; deve ser bloqueado ate a revisao das referencias.
12. Com `Aplicar limites organizacionais` desligado, confirmar que o CRM mantem a visibilidade anterior.
13. Ativar a opcao para um usuario de teste que possua escopo configurado; confirmar que seus proprios registros ficam restritos as empresas/unidades autorizadas.
14. Confirmar que a ativacao nao concede registros de outros responsaveis e nao altera o acesso de administrador.
15. Testar Leads, Negocios, Propostas, Pedidos, Contratos, Atividades e Customer 360 para regressao.
16. Testar Service Desk, Projetos, Minha Agenda, Conversas, Campanhas e Telefonia para confirmar ausencia de regressao indireta.

## Validacoes de codigo executadas nesta entrega

- `ruby -c` nos arquivos Ruby novos/modificados relacionados.
- `node --check` nos modulos JavaScript e nos blocos `<script setup>` das telas Vue alteradas.
- parse JSON das traducoes `pt_BR` e `en`.
- verificacao das chaves i18n usadas pela nova tela.
- comparacao de hashes com o ZIP pai para confirmar zero arquivos removidos.
- hash de `db/schema.rb`, lockfiles e Docker conferido sem alteracao.

## Nao executado neste ambiente

- Rails boot completo;
- migrations em PostgreSQL;
- RSpec (Bundler/Ruby do projeto nao disponiveis no ambiente atual);
- compilacao Vue/Vite completa;
- browser/E2E;
- Docker;
- PABX/SIP/WebRTC.

O pacote continua sendo candidato de codigo-fonte para homologacao, nao versao de producao homologada.
