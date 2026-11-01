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

Na entrega inicial descrita nesta seção, não foram adicionados modelos de processo, migrations, dependências, integrações externas, execução automática do NICO ou solicitações sem pedido. A atualização candidata ao final deste documento registra o escopo posterior e suas pendências.

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

## Versão candidata de homologação — atualização de 01/11/2026

Esta seção complementa a entrega inicial descrita acima. O Backoffice continua parcial em relação ao Word; a candidata não representa a conclusão integral do projeto.

A implementação aprovada em `a2db8b6d` acrescenta versões documentais imutáveis, decisões humanas com motivo e pré-análise local por Poppler/Tesseract. A pré-análise preserva evidências estruturadas e confiança medida, exige revisão humana e não aprova documentos automaticamente. A fila de processamento documental é `low`.

As migrations necessárias são `20261101190000` (versões, análises e decisões documentais) e `20261101200000` (versão do fluxo). Registros existentes permanecem no fluxo 1; novos atendimentos de execução usam o fluxo 2: análise/documentação, aprovação quando exigida, contrato, implantação, provisionamento e financeiro. Contrato e assinatura continuam sujeitos aos serviços e políticas nativos. A imagem precisa de Poppler, Tesseract e idiomas `por`/`eng`.

A correção dos gates preserva esse fluxo e fecha o intervalo de proteção financeira entre a aprovação registrada do pedido e a geração do contrato. A proteção anterior por proposta aceita ou contrato existente continua válida para registros legados. Os testes HTTP cobrem tentativas de alterar itens, desconto e frete efetivo, antes e depois do contrato e durante aprovação operacional pendente.

Os dois testes antigos de navegação verificavam setas de rolagem removidas pelo layout aprovado. A regressão atual verifica destinos únicos, seleção após mudanças de rota, grupos, fechamento por seleção/Escape e revogação das opções administrativas. O componente real também foi exercitado em Chromium em 360, 768 e 1366 pixels, nos temas claro e escuro.

Três expectativas globais `Message.count == 0` do Service Desk confundiam as operações internas com duas mensagens sintéticas de propostas criadas pelos testes PostgreSQL de concorrência da Central de Aprovações. O reproduzidor na base `ee9c1aa3f2957b5a58d4dfaf33f71fc398b56606` confirma a mesma condição. As regressões corrigidas exigem que a operação e seu replay não alterem o total global de mensagens, que a conta do chamado continue sem mensagens e que `SendReplyJob` não seja solicitado; os registros de concorrência são preservados. Notas internas e tarefas continuam verificados separadamente, incluindo unicidade e visibilidade.

O teste SMTP não configurava `FRONTEND_URL`, obrigatória para renderizar o link do chamado. Isso também foi reproduzido na base. O fixture agora declara URL sintética e usa o adaptador de e-mail de teste. Preferência explícita, autorização do retry e estado desconhecido continuam obrigatórios; configuração ausente ou resultado incerto não são convertidos em aceite. Aceite SMTP continua distinto de entrega ao destinatário.

### Limitações e pendências preservadas do Word

- Portal do cliente e concessões de acesso; classificação/extração estruturada de outros tipos documentais e verificações de validade/legalidade.
- Antimalware e políticas de retenção/criptografia implantadas; visualizador incorporado e pacote documental ZIP/resumo final.
- Linha do tempo e lembretes completos da Central; revisões/diffs contratuais imutáveis e provedores externos de assinatura com seus callbacks.
- BI e exportações avançadas por perfil; NICO contextual e passagem para CS.
- Idempotência de todos os comandos além do upload e das unicidades nativas; respostas externas/equipes em pendências e abertura automática de pendência por rejeição documental.

### Gates e publicação controlada

`backoffice-flow.yml` valida as migrations em `backoffice_test`, dependências OCR, testes HTTP e comissões. O RSpec ampliado coleta o plano completo e o divide em duas execuções obrigatórias: regressão principal e concorrência do Service Desk, em bancos descartáveis separados. A execução concorrente usa um nome já aceito pelos guards nativos e ambos os opt-ins. Um validador compara os IDs executados com todo o plano e rejeita omissões, duplicidades, falhas ou exemplos pendentes. Essa separação preserva as evidências confirmadas por conexões independentes sem contaminar os demais testes do Service Desk. Projetos, operações, NICO e contatos têm uma etapa própria de regressão.

`build-ghcr.yml` exige o mesmo SHA e uma execução bem-sucedida do gate nativo para publicar a candidata. O build testa frontend e identifica o SHA interno. O smoke inicia Rails e Sidekiq com a mesma imagem em rede, armazenamento e banco exclusivos, exige heartbeat e processamento OCR real na fila `low`. Somente depois pode publicar uma tag SHA ainda inexistente no GHCR. Nenhum desses fluxos implanta produção, executa migrations em produção ou substitui `latest`.

Os resultados efetivos, URLs de execução, SHA final e eventual digest devem ser consultados no relatório da rodada e nos workflows. Uma tag planejada ou uma rota HTTP 200, isoladamente, não demonstram publicação nem aprovação do fluxo.
