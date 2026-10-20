# Grupo JRC: candidato de estabilidade de 20/10/2026

Este documento descreve mudanças locais candidatas. Não comprova instalação nem
funcionamento em produção. Nenhum bot, fluxo ou política de distribuição foi
ativado no servidor por esta implementação.

## Responsabilidades dos sistemas

| Sistema | Responsabilidade |
| --- | --- |
| Broker | Conexões WhatsApp/Meta, transporte, eventos, execução da URA e transferência para a central configurada. |
| JRC Conversas | Account, caixas, membros, times, permissões e distribuição do atendimento humano. |
| NICO | Assistente privado do operador, consultas e ações autorizadas; envio ao cliente mantém a prévia e o controle de atendimento existentes. |

O Broker continua usando o contrato de integração de cada instalação. A nova
política de distribuição é implementada no JRC Conversas; ela não é instalada
automaticamente em um Chatwoot de terceiros.

As alterações do NICO desta rodada ficam na integração Rails/Sidekiq e no
frontend do JRC Conversas. O serviço separado `nico-runtime` foi testado e
permaneceu sem alteração de código. No Broker, o ajuste funcional desta rodada
é a aceitação dos tipos de tarefas de grupos na listagem/API, acompanhada da
atualização do contrato OpenAPI e de regressões.

## Três empresas na mesma Account

Gopure, Construtora e Operadora compartilham o cadastro e a administração do
Grupo JRC. Cada empresa mantém sua caixa e seu número. Suporte e Financeiro
podem ser times compartilhados; Comercial deve ter um time por empresa.

Um agente pode participar das três caixas e dos times em que trabalha. A lista
“Minhas” reúne as conversas atribuídas a ele, identificadas pela caixa original.
“Todas” continua sendo uma visão agregada sujeita às permissões do usuário:
atribuir uma conversa não a remove dessa visão.

Após a URA escolher um time, a política candidata procura agentes:

1. pertencentes à Account, à caixa e ao time;
2. disponíveis, com presença online;
3. abaixo do limite agregado de conversas abertas da Account;
4. respeitando também a capacidade nativa da caixa.

Escolhe quem tem menos conversas abertas, somando todas as caixas desta
Account. O desempate alterna agentes. Uma transação serializa as escolhas por
Account para evitar que duas caixas consumam a mesma última vaga simultaneamente.
Conversas de outros tenants não entram nessa contagem.

Sem agente elegível, o atendimento permanece aberto no time, sem responsável.
A recuperação periódica tenta distribuir novamente, sem reiniciar o bot.
Conversas pendentes, sob controle de bot/NICO/Flow ou já atribuídas não são
tomadas pelo distribuidor.

## Configuração após instalar uma candidata aprovada

No JRC Conversas, o administrador encontra a política na página do módulo
Broker. Ela começa **desligada**, sem caixas selecionadas. Selecionar as três
caixas, informar a capacidade e salvar é uma ação explícita; abrir a tela não
ativa a distribuição. O servidor rejeita caixas de outra Account.

Antes de ativar em homologação:

- conferir os membros das três caixas e dos cinco times;
- manter o autoatendimento/saudação concorrente da caixa desligado conforme
  a preparação exigida pelo Broker;
- permitir atribuição automática nos times de destino;
- configurar o nó de transferência da URA para o time correto, preservando a caixa;
- deixar o número de teste isolado dos clientes reais.

Nas caixas selecionadas, a atribuição automática antiga deixa de antecipar a
seleção do time. Isso é necessário para a URA decidir o destino. As demais
caixas, incluindo e-mail e atendimento sem URA, mantêm suas regras anteriores.
A carga usada na seleção continua somando todas as conversas abertas do agente
na Account, inclusive nas outras caixas.

## NICO assíncrono

O endpoint grava o pedido e responde com estado de processamento. O Sidekiq
prepara a resposta fora da requisição web. A tela acompanha o resultado,
apresenta a resposta e, quando solicitado, a lê em voz alta uma única vez.
Não reproduz respostas antigas ao abrir o painel.

O mesmo pedido não é enviado novamente ao provedor por uma entrega duplicada
do job. Pedidos nunca iniciados podem voltar à fila. Uma execução iniciada e
interrompida fica com resultado incerto; não há reenvio automático nem liberação
das reservas de consumo anteriores.

As permissões são revalidadas no processamento e no retorno do provedor.
O NICO preserva as consultas manuais autorizadas pela política nativa do
administrador. O Helpdesk automático exige também vínculo operacional ativo.

Rails e Sidekiq devem usar a mesma imagem candidata e carregar a programação de
jobs. Esta mudança utiliza tabelas e atributos existentes: não acrescenta
migração de banco nem exige troca de chaves, URLs ou credenciais do runtime.

O planejamento usa a fila `default` já atendida pela configuração atual. Isso
remove a espera da requisição HTTP, mas continua ocupando uma vaga do Sidekiq
durante a chamada de IA. Com concorrência 2, dois pedidos longos podem atrasar
outros jobs. Medir espera das filas e dimensionar/isolar o processamento de IA
é um critério de capacidade antes de ampliar o uso; esta entrega não comprova
esse dimensionamento.

## Limites da validação

Testes locais com PostgreSQL, Redis, navegador e provedores simulados verificam
contratos e regressões. Não comprovam entrega no WhatsApp real, configuração
Meta, áudio no navegador do operador, integração de um Chatwoot externo ou
capacidade para 500 empresas/10 mil conexões.

A aprovação para produção requer confirmar a imagem em execução e realizar
uma jornada controlada no ambiente instalado: entrada, URA, transferência,
atribuição, resposta humana, pausa do bot, reconexão e consulta/ação do NICO.
Essa jornada não autoriza ativar bots para toda a base.

## Evidências locais desta rodada

| Verificação | Resultado observado |
| --- | --- |
| Rails: NICO, Flows, Broker, permissões, distribuição e e-mail | 725 exemplos distintos aprovados na consolidação por arquivo/descrição da rodada integrada e rechecks |
| Distribuição + caminhos nativos + API Broker | 98 exemplos aprovados; após refatoração interna, os 17 exemplos específicos da política/concorrência passaram novamente |
| UI NICO e página de conexões | Recheck de 59 testes aprovado; seleção final de caixas/página de conexões com 12 testes aprovados |
| Runtime NICO | 39 testes aprovados e typecheck sem erro; runtime não alterado nesta rodada |
| Sandbox de Flow | 5 testes aprovados |
| Broker geral | 3.227/3.231 na primeira rodada; quatro timeouts passaram no recheck dos dois arquivos (10 testes) |
| Broker PostgreSQL | 1.196 aprovados, 12 falhas e 33 não executados inicialmente; oito arquivos reexecutados (182/183), último cenário corrigido/retestado junto aos quatro gates de prazo |
| Broker navegador local | 37 jornadas aprovadas, zero falhas; cinco combinações ignoradas por se aplicarem exclusivamente a desktop ou celular |
| Broker build/bundle | Compilação aprovada; scanner do bundle com 11 arquivos e zero achados |
| JRC frontend de produção | Vite final aprovado, 5.442 módulos, 9m33s e saída 0 |
| Revisão independente | Correção de escopo administrativo aplicada; duas verificações dirigidas posteriores sem novos achados |

A consolidação Rails exclui uma cópia acidental de diretório de testes dentro
do container descartável. Os 53 testes inicialmente condicionais foram
executados com opt-in em bancos locais explicitamente permitidos: 18 gates de
envio e 35 cenários de e-mail. Nenhuma regra de autorização, prazo de produção
ou trava de consumo foi relaxada para obter aprovação.

As correções adicionais nos testes do Broker tratam a ordenação diferente de
`text` e `pg_catalog.name` no PostgreSQL e separam o prazo da preparação do
cenário do prazo curto da operação testada. Falhas e rechecks permanecem
registrados; não se apresenta a primeira rodada como inteiramente aprovada.

O build JRC ainda avisa sobre chunks grandes, importação estática/dinâmica do
webphone e base Browserslist antiga. A imagem pública
`public/brand-assets/jrc-background.jpeg`, referenciada em runtime, foi
confirmada no repositório. Esses avisos não impediram a compilação, mas a
performance visual precisa ser medida no ambiente real.

Estado na conclusão dos testes locais: alterações candidatas e evidências
registradas. Em 20/10, o usuário autorizou concluir a entrega e gerar imagens
após esses testes. A publicação será confirmada pelo workflow e pelo digest,
separadamente do deploy. Não marcar a integração implantada como 100% validada.

## Preparação da atualização

- A imagem do JRC deve ser a mesma nos serviços `rails-grupo-jrc`,
  `sidekiq-grupo-jrc` e `chatwoot-init-grupo-jrc`, herdada da âncora existente.
- O NICO desta entrega acompanha essa imagem. O `nico-runtime` separado não
  teve alterações; conservar seu digest e sua URL/token já configurados.
- Não existem migrations novas nesta rodada. Se a instalação já está na
  base `4633cc5c09c20d44694a95155375b208efbff69f` com migrations aplicadas,
  esta atualização não exige SQL manual.
- No terminal Rails, após o deploy, usar `/bin/sh`, executar `cd /app`,
  `cat /app/.git_sha` e `bundle exec rails db:abort_if_pending_migrations`.
  Conferir também `/app/.git_sha` no Sidekiq.
- No Broker, instalar o par API/web do mesmo SHA, conservar o Compose
  `infra/dokploy/compose.yaml` e executar no container API
  `node /app/apps/api/dist/commands/operational-status.js`. A baseline desta
  entrega continua `0068_flow_domain_commands`.
- Nenhuma dessas verificações habilita uma URA ou a política de atribuição.
  A seleção das caixas e a jornada de homologação são etapas posteriores,
  controladas pelo administrador.
