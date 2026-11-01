# Backoffice: Central de Operações, primeira entrega

Base: Grupo JRC, commit `e4a6a007193988af3f314a902ec68531fd25a14a`. Esta entrega reorganiza a operação existente, sem criar outro motor comercial ou alterar o schema.

## Telas e compatibilidade

- `/crm/backoffice` e `/crm/backoffice/overview`: indicadores calculados no servidor, distribuição das solicitações ativas por etapa e fila, e registros recentes.
- `/crm/backoffice/mine`: cartões com as solicitações do usuário autenticado, filtros e paginação.
- `/crm/backoffice/requests`: filas com filtros e paginação. `/crm/backoffice/queues` aponta para a mesma apresentação.
- `/crm/backoffice/requests/:requestId`: Detalhe 360, com contexto comercial, contrato, documentos, execução, pendências, histórico e dependências da etapa.
- As demais seções e o nome de rota `crm_backoffice` permanecem disponíveis. As ações especializadas continuam na implementação existente; o Detalhe 360 abre essas áreas com a solicitação selecionada.
- Nova solicitação utiliza o formulário e o endpoint existentes. Avançar, bloquear/retomar e reabrir utilizam as ações nativas, com auditoria e validação no servidor.

Os caminhos acima são relativos a `/app/accounts/:accountId`. As permissões e o feature flag do CRM continuam obrigatórios.

## Consulta paginada

Novo endpoint: `GET /api/v1/accounts/:account_id/crm/backoffice_requests/workspace`.

Parâmetros opcionais:

| Campo | Comportamento |
| --- | --- |
| `view=mine` | Restringe ao usuário autenticado no servidor; não recebe uma identidade do navegador. |
| `q` | Busca por número, título, cliente, pedido ou responsável. Até 200 caracteres; curingas SQL são escapados. |
| `kind`, `stage`, `priority`, `status` | Filtros dos valores existentes. `status=active` usa `BackofficeRequest::ACTIVE_STATUSES`. |
| `owner_id`, `operations_queue_id`, `business_unit_id` | Somente restringem a relação previamente autorizada. Não concedem acesso. |
| `overdue=true` | Prazo operacional ou SLA total, da etapa ou da primeira ação vencido, entre solicitações ativas. Os relógios de SLA pausados usam o instante da pausa. |
| `sort` | `recent` (padrão), `oldest`, `priority` ou `deadline`. Ordenação com desempate por ID. |
| `page`, `per_page` | Página mínima 1, ajustada à última disponível; 20 registros por padrão, máximo 50. |

Resposta: `{ data, meta: { total, page, per_page, pages }, summary, options }`.

`data` contém somente identificação da solicitação, etapa/status/prioridade, datas, referências resumidas de cliente/pedido/responsável/unidade/fila e snapshot do relógio existente. Não inclui metadata, documentos, e-mail, snapshot comercial completo ou histórico. O detalhe continua sendo consultado pelo `show` existente.

`summary` usa a mesma relação filtrada da lista inteira, sem depender da página carregada. Distribuições por etapa e fila incluem somente solicitações ativas. As opções de filtro vêm dos registros visíveis ao usuário, com até 100 opções por categoria.

O endpoint antigo de listagem mantém a resposta em array para preservar seus consumidores. O `show` acrescenta fila, SLA e `stage_blockers`; o histórico passa a explicitar o filtro de conta.

## Autorização e regras

A relação parte de `crm_scope.jrc_crm_backoffice_requests` e passa por `visible_to_current_user`, incluindo a restrição por responsável dos agentes e as regras de `OrganizationalVisibility`/`CorporateCoverage`. Nenhum parâmetro substitui `Current.user` ou `Current.account`.

`BackofficeRequest#stage_blockers` é a extração somente de leitura das dependências já verificadas por `advance!`. O avanço continua revalidando essas dependências, os gates comerciais e as assinaturas, sob os locks existentes. A prévia não é autorização para executar uma ação. Os componentes de aprovação existentes mostram os gates comerciais no detalhe.

Não foram adicionados modelos de processo, migrations, dependências, integrações externas, execução automática do NICO ou solicitações sem pedido. A normalização de metadata e o construtor de processos permanecem para as próximas entregas.

## Validação

Frontend:

```sh
pnpm exec vitest run app/javascript/dashboard/routes/dashboard/crm/views/spec/BackofficeWorkspace.spec.js app/javascript/dashboard/routes/dashboard/crm/views/spec/CommercialViews.spec.js
pnpm exec vitest run app/javascript/dashboard/routes/dashboard/crm/views/spec/BackofficeLegacyFlow.spec.js app/javascript/dashboard/routes/dashboard/crm/views/spec/ContractSignatureDate.spec.js
```

Integração HTTP real, com banco descartável já preparado e dependências de teste instaladas:

```sh
RAILS_ENV=test bundle exec rails runner test/integration/backoffice_workspace_test.rb
RAILS_ENV=test bundle exec rails runner test/integration/backoffice_commercial_flow_test.rb
```

Os testes HTTP verificam autenticação, módulo desabilitado, isolamento entre contas, responsável, operadora e unidade, paginação, ordenação, filtros combinados, escape de busca, SLA pausado, prévia sem escrita, dependências bloqueantes e auditoria após o avanço nativo. Cada teste usa uma transação revertida ao final.

Na validação local desta entrega, a imagem Ruby existente não continha MockRedis. Um adaptador local ignorado pelo Git substituiu somente os pools de teste por Redis real e exclusivo. A aplicação Rails e as requisições HTTP usaram os controllers, rotas, models e serviços desta branch. As capturas de navegador usaram componentes reais com APIs simuladas e dados sintéticos; elas não representam uma homologação em produção.

### Validação completa do fluxo

Uma segunda rodada percorreu os componentes reais pelo navegador, em `America/Sao_Paulo`, conectados ao servidor Rails e a PostgreSQL/Redis descartáveis. A aprovação do pedido, envio e validação documental, assinatura manual com PDF, checklist, provisionamento, emissão da fatura, pagamento, resolução de pendência e conclusão foram executados com respostas e persistência reais. Dados, documentos de teste e confirmação de execução permanecem sintéticos; nenhum serviço externo de assinatura ou provisionamento foi acionado.

Essa rodada encontrou e corrigiu dois problemas: o formulário de assinatura preenchia UTC em um campo `datetime-local`, gerando uma data futura no fuso de São Paulo; e a mudança de área após avançar perdia a solicitação selecionada. A assinatura usa a hora local e a navegação preserva `requestId`. As validações de horário e dependências no servidor permanecem obrigatórias.

A suíte ampliada também verifica download dos documentos persistidos, recusa de assinatura futura, pagamento com implantação pendente e o caminho com Projeto de Implantação: o pedido não pode ser concluído sem tarefas finalizadas e aceite do projeto. O workflow `.github/workflows/backoffice-flow.yml` repete os testes HTTP em banco descartável para pull requests e execução manual; ele não publica nem implanta a aplicação.
