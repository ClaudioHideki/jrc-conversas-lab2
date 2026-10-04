# JRC Conversas — Fluxo comercial ponta a ponta Nexora

Data: 04/10/2026
Status: candidato para homologação em LAB

## Objetivo

Validar e fortalecer o fluxo de uma empresa fictícia única no Cadastro Mestre, sem recriar Empresa ou Contato ao avançar pelas etapas do CRM e do pós-venda.

Cenário de referência:

- Empresa: **Nexora Tecnologia Ltda. / Nexora Tech**
- Relacionamento inicial: **Prospect**
- Contato: **Marcelo Andrade**
- Responsável comercial: **Thiago Ribeiro**
- Produto: **JRC Conversas — 10 usuários**
- Mensalidade de teste: **R$ 1.000,00**
- Implantação de teste: **R$ 1.200,00**

## Fluxo coberto

1. Cadastro Mestre: Empresa + Contato únicos.
2. Lead qualificado vinculado à mesma Empresa e ao mesmo Contato.
3. Conversão atômica do Lead em Negócio.
4. Atividade de demonstração vinculada ao Negócio/Empresa/Contato.
5. Proposta comercial vinculada ao Negócio.
6. Aceite interno ou público da proposta.
7. Negócio movido para etapa de ganho, quando o funil possui etapa `is_won`.
8. Empresa promovida de Prospect/Lead para Cliente no mesmo registro do Cadastro Mestre.
9. Pedido criado de forma idempotente a partir da proposta aceita.
10. Requisitos de contrato/implantação/follow-up preservados no snapshot operacional do pedido.
11. Após aprovação do pedido, contrato principal criado/reutilizado de forma idempotente.
12. Backoffice criado/reutilizado.
13. Projeto de Implantação criado/reutilizado quando solicitado e quando Projetos/permissões estão disponíveis.
14. Projeto recebe tarefas padrão: Kickoff, Levantamento, Configuração, Integrações, Treinamento, Homologação e Go-live.
15. Assinatura contratual, checklist de implantação e recebimento continuam como gates reais.
16. Fatura e pagamento existentes alimentam o fechamento do backoffice.
17. Customer 360 permanece apontando para a mesma Empresa e consolida Lead, Negócio, Atividade, Proposta, Pedido, Contrato e Projeto.

## Alterações principais

- `JrcCrm::AcceptedProposalLifecycleService`: orquestra o pós-aceite de forma idempotente.
- `JrcCrm::OrderContractService`: cria/reutiliza o contrato principal no backend.
- `JrcCrm::OrderImplementationProjectService`: cria/reutiliza Projeto de Implantação e o vincula ao Negócio.
- `JrcCrm::OrderWorkflowSyncService`: passou a sincronizar contrato + implantação + backoffice no fluxo operacional do pedido.
- Aceite interno e público de propostas utiliza a mesma orquestração.
- Wizard de Pedido recebeu a opção explícita **Criar Projeto de Implantação**.
- Novo teste de integração `spec/services/jrc_crm/nexora_end_to_end_spec.rb`.

## Decisões de segurança funcional

- Nenhuma Empresa paralela do CRM é criada.
- Nenhum Contato é recriado durante conversão/venda.
- Reexecução do aceite não duplica Pedido.
- Reexecução do workflow não duplica Contrato, Backoffice ou Projeto de Implantação.
- Falta de permissão para criar Projeto não desfaz a venda; o Backoffice recebe aviso para correção operacional.
- Pagamento não ignora pendências de assinatura/implantação.
- Uma proposta aceita não é revertida se um passo de pós-venda falhar; o erro é retornado para tratamento, preservando a evidência comercial.

## Fora deste pacote

Este pacote não altera a modelagem de Funis e Etapas e não cria regras específicas para desconto/aprovação além das já existentes. Também não força emissão automática de fatura, pois regras financeiras podem variar por produto, contrato e conta.
