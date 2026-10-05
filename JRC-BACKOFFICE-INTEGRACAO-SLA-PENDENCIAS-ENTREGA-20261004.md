# JRC Conversas — Backoffice integrado, documentação, pendências, filas e SLA

Data do candidato: 04/10/2026

## Objetivo

Fechar a rastreabilidade operacional do Backoffice sem criar cadastros paralelos ao CRM. A cadeia preservada é:

**Cliente → Negócio → Proposta → Pedido → Contrato → Solicitação Backoffice → Documentação/Pendências → Implantação/Provisionamento/Financeiro**.

## 1. Pedido → Backoffice

- A tela **Nova solicitação** não usa mais uma lista genérica e opaca de Pedidos.
- Foi criado um endpoint de seleção **somente leitura** que classifica os Pedidos em:
  - elegíveis;
  - aguardando condição/status;
  - já vinculados.
- Para `fulfillment`, a regra explícita de elegibilidade é: `approved`, `separating`, `invoiced`, `shipped` ou `completed`.
- Pedido `canceled` nunca é elegível.
- Pedido já ligado a uma Solicitação de fulfillment não gera duplicidade.
- O seletor apresenta número, cliente, produtos/serviços, valor, MRR e status; a seleção preserva referências para Negócio, Proposta, Contrato, responsável e Unidade.
- O endpoint de consulta não cria nem altera registros.
- Para novas vendas, a automação já existente em `OrderWorkflowSyncService` continua responsável por criar/reutilizar a Solicitação quando o Pedido entra em status comercial elegível.

## 2. Contrato único

O Backoffice continua referenciando `JrcCrm::Contract`. **Não foi criada uma segunda entidade de Contrato**. A Solicitação usa o contrato originado do CRM/Pedido.

## 3. Documentação

- Toda documentação permanece vinculada a uma **Solicitação Backoffice**.
- É possível selecionar uma Solicitação mesmo quando ela ainda não possui anexos.
- Checklist documental suporta:
  - obrigatório/opcional;
  - bloqueante/não bloqueante;
  - requisito condicional por origem do Pedido, tipo de Solicitação, prioridade, produto, Unidade e dados do snapshot comercial.
- Documento obrigatório não pode ser aprovado sem anexo.
- Rejeição/expiração de requisito bloqueante coloca a Solicitação em estado bloqueado.
- Quando todos os requisitos documentais bloqueantes estiverem aprovados, a etapa documental é liberada automaticamente e o motor valida o próximo gate antes de avançar.
- Cada validação registra chave/documento, status anterior, novo status, usuário e data/hora em `document_validations` e na auditoria CRM.

## 4. Pendências

Toda Pendência continua dentro da Solicitação e mantém o encadeamento account → cliente → pedido → solicitação.

Campos/controles incluídos:
- tipo;
- descrição/motivo;
- origem;
- área responsável;
- usuário responsável;
- prioridade;
- prazo/SLA;
- bloqueante SIM/NÃO;
- evidências/anexos;
- solução;
- histórico.

Comportamentos:
- Pendência bloqueante muda a Solicitação para `blocked` e impede o gate de Pendências.
- **Devolver** exige responsável e registra devolução/histórico; quando existe Negócio, tenta criar uma atividade/tarefa CRM para o responsável.
- **Resolver** exige texto de solução e registra responsável/data/hora.
- Pendência resolvida pode ser reaberta, preservando o histórico.
- Não existe endpoint de exclusão silenciosa de pendência processada.

## 5. Motor central de Filas e SLA

Foi criado `JrcOperations`, propositalmente genérico, para não implementar um motor exclusivo do Backoffice. O modelo admite escopos futuros como Service Desk, CRM, Implantação e Relacionamento.

### Filas

Configuração por:
- empresa operacional;
- Unidade;
- tipo de Solicitação;
- produto;
- prioridade;
- equipe;
- responsável preferencial;
- especialidade.

Estratégias:
- Manual;
- Round Robin;
- Menor Carga;
- Especialidade/Regra.

Toda nova Solicitação recebe uma fila e uma política. Quando não existe configuração comercial específica, é criado um fallback **Backoffice Geral** + política de monitoramento sem inventar prazo de SLA.

### SLA

Cada política pode definir:
- SLA de primeira ação;
- SLA da etapa;
- SLA total;
- calendário/dias/horários;
- feriados;
- status que pausam o SLA;
- alertas configuráveis (padrão 50%, 75%, 90%, 100%);
- responsável de escalonamento.

O relógio registra pausas/retomadas e desloca os vencimentos pelo período pausado.

### Monitoramento

Job agendado a cada 5 minutos:
- registra thresholds atingidos;
- cria atividade operacional para thresholds críticos quando existe Negócio/responsável;
- executa escalonamento configurado após violação/100%;
- registra auditoria de threshold e escalonamento.

Dashboard de SLA/Filas apresenta:
- dentro do prazo;
- 50% consumido;
- atenção;
- crítico;
- vencido;
- primeira ação vencida;
- cumprimento percentual de SLA em Solicitações concluídas com SLA;
- tempo médio de resolução;
- volume/estado por fila;
- quantidade de filas e políticas configuradas.

## 6. Migrações

Este candidato adiciona duas migrations PostgreSQL:

- `20261004234000_create_jrc_operations_routing_and_sla.rb`
- `20261004234100_backfill_jrc_operations_backoffice_routing.rb`

A segunda migration vincula Solicitações existentes a uma fila/política fallback sem criar prazos artificiais.

## 7. Pontos intencionalmente não fechados neste pacote

- **Aprovações:** a tela atual permanece com decisão explícita e auditável. Não foi criado um novo motor genérico de aprovação porque a homologação funcional desta área ainda será feita.
- **Relatórios:** não foi redesenhado nesta etapa; deve ser validado em seguida.
- **NICO:** não foi criada uma automação nova de IA. O motor agora fornece dados estruturados de fila, pendência, SLA e auditoria que poderão alimentar a evolução futura do copiloto operacional.

## 8. Status de validação

Validações estáticas realizadas no ambiente de geração:
- sintaxe Ruby dos arquivos Ruby alterados/adicionados: OK;
- `config/schedule.yml`: YAML válido;
- JavaScript da API: parse OK;
- scripts dos componentes Vue alterados: parse OK;
- migrations: timestamps sem duplicidade;
- nenhum hardcode Nexora/Marcelo no runtime.

Não executado neste ambiente por ausência de dependências:
- migration PostgreSQL real;
- RSpec;
- Vue/Vite/Vitest completo;
- browser;
- Docker/GHCR.

Este pacote permanece **CANDIDATO PARA HOMOLOGAÇÃO NO LAB**.
