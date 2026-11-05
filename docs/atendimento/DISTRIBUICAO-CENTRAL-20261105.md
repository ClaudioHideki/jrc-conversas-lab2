# Distribuição central de conversas — candidata local de 05/11/2026

## Resultado e limites

Implementação no JRC Conversas LAB2, baseada em `5dcf046b63eb79740b30d76893828f4cbed52280`, branch `codex/shared-inbox-history-20261104`. O checkout estava limpo no início. O trabalho anterior de histórico, agrupamento por caixa e integração Broker foi preservado.

Esta candidata não foi publicada, implantada ou ativada em nenhuma caixa real. Não houve envio de WhatsApp, alteração de credenciais, sessão, engine, configuração produtiva, backup, dump ou restore. O repositório Broker não recebeu alterações neste incremento. Nenhuma migration nova foi criada.

## Comportamento implementado

- Política aditiva por caixa: `shared` mantém o comportamento compartilhado; `assigned_only` restringe o agente às conversas atribuídas a ele. Administradores e supervisores designados podem acompanhar a fila e as conversas, respeitando RBAC e vínculo atual com a caixa.
- A exclusividade é aplicada no servidor: acesso direto, listagens, busca de mensagens/conversas, histórico por contato, participantes, notificações, contadores e realtime. Participar de um time, receber uma menção ou conhecer a URL não libera a conversa de outro agente.
- Transferências revogam o cache do antigo responsável sem enviar conteúdo privado. Jobs de realtime, push e e-mail verificam a autorização novamente antes da entrega.
- O navegador descarta respostas HTTP iniciadas antes da revogação. Limpa conversa, mensagens, anexos, resultados de busca, notificações e histórico em cache; na reconexão busca uma página completa e revalida a conversa aberta.
- A mudança de visibilidade produz evento de auditoria PostgreSQL. A invalidação de contadores e o aviso aos painéis são enfileirados após COMMIT, por `VisibilityChangedJob`. O contador também compara a política atual com a política do snapshot; não reutiliza o snapshot de uma autorização anterior, mesmo antes de o job executar. Em caixas centrais, snapshots obsoletos não são usados como fallback de conteúdo.
- Limite individual por agente e por caixa, disponibilidade obrigatória e seleção pela menor ocupação proporcional. Exemplo: 6/20 (30%) precede 4/5 (80%). Empate usa round robin. As políticas compartilhadas anteriores mantêm seu limite agregado legado.
- Decisão de capacidade revalidada sob locks PostgreSQL existentes de account/conversa/membro; fila ordenada pela primeira solicitação e ID. Nova mensagem não reinicia a posição na fila. Editar a política não deixa solicitações já admitidas para trás.
- Pausar um agente preserva seus atendimentos. Voltar ao disponível ou recuperar a presença após expiração acorda a fila. Reabrir tenta o responsável anterior somente se ainda estiver elegível e com capacidade; caso contrário redistribui.
- URA nativa é opcional. Quando presente escolhe o time e registra preferência, sem ignorar disponibilidade/capacidade nem entregar enquanto o Flow estiver ativo. A conclusão do Flow acorda a fila humana. Sem URA, o time padrão configurado segue a mesma seleção humana.
- Histórico importado continua fora da admissão automática. Nenhuma importação retroativa de todo o WhatsApp foi executada ou homologada aqui.
- O painel de distribuição inclui visibilidade, supervisores e limites individuais. O histórico registra atribuições e razão da decisão sem textos de mensagens ou credenciais.

## Configuração após revisão e publicação

No módulo Conectar seu WhatsApp, abrir a caixa e sua configuração de Distribuição. Para uma caixa central:

1. Cadastrar os agentes na caixa e nos times que realmente atendem aquele número.
2. Selecionar atendimento exclusivo (`assigned_only`), ativar a distribuição e escolher os times elegíveis.
3. Definir os supervisores da própria caixa e a capacidade de cada agente; manter disponibilidade, capacidade e fila de espera ativas.
4. Se houver URA, configurar as opções do Flow para os times habilitados. Se não houver, usar o time padrão da distribuição.
5. Homologar com dois agentes e um supervisor antes de ativar na caixa corporativa.

A caixa pessoal pode continuar `shared`. Não ativar a exclusividade automaticamente em todas as caixas: isso mudaria a regra aprovada para caixas pessoais compartilhadas.

## API existente ampliada, sem quebra de versão

Prefixo: `/api/v1/accounts/:account_id/jrc_broker/inboxes/:inbox_id`.

| Método e rota | Resultado |
| --- | --- |
| GET `/distribution` | Política, agentes, disponibilidade, capacidade e fila da caixa; requer gestão administrativa. |
| PUT `/distribution` | Valida e grava política por caixa, com auditoria. |
| GET `/distribution-history` | Histórico paginado das mudanças de política, exclusivo da administração. |
| GET `/history` | Histórico de conexão e atribuição; membros recebem metadados reduzidos segundo a autorização existente. |

Novos campos de PUT: `visibility` (`shared` ou `assigned_only`), `supervisor_ids` (IDs de membros da caixa), `agent_limits` (objeto com ID string e inteiro de 1 a 100). As opções anteriores de calendário, times, fallback e capacidade permanecem. Cliente antigo que omite os novos campos preserva a configuração já salva. JSON inválido ou combinação insegura retorna o contrato existente de erro, sem gravação parcial.

Evento novo de atribuição: `DISTRIBUTION_ASSIGNED`, com IDs, time, ocupação/capacidade, instante de solicitação e motivo. Os nomes internos dos eventos de revogação são `conversation.access_revoked` e `conversation.access_reset` e não levam conteúdo de conversa.

## Revisão de segurança e regressão

A revisão independente identificou seis pontos importantes, reproduzidos e corrigidos: reutilização de conversa alheia no POST de criação; e-mail já enfileirado após transferência; cache/reconexão e respostas HTTP atrasadas; contadores agregados de colegas; edição de política que excluía solicitações antigas; reabertura HTTP que atribuía agente pausado. A revisão final acrescentou proteção dos snapshots de contadores e a publicação de mudanças somente depois do COMMIT.

O usuário que já visualizou uma mensagem não pode ser obrigado a esquecê-la. URLs privadas assinadas já emitidas mantêm a validade prevista até expirar; limpeza de cache não equivale a revogação instantânea dessas URLs. A publicação do aviso de alteração continua dependendo da fila; a autorização HTTP é conferida no servidor e a reconexão limpa o cache independentemente desse aviso.

## Testes executados

- RSpec ampliado: **285 exemplos, 0 falhas**, com PostgreSQL e Redis locais descartáveis; gate de concorrência habilitado (`JRC_SD_CONCURRENCY=1`) em banco de teste dedicado.
- Vitest: **23 arquivos, 219 testes, 0 falhas**, incluindo configuração, reconexão, cache revogado, buscas, notificações e agrupamento existente.
- Prettier: todos os arquivos JS/Vue/JSON alterados formatados.
- ESLint: **0 erros, 22 avisos** (i18n/template); não declarar lint integral limpo.
- RuboCop Lint: **45 arquivos, 0 ofensas**. O lint completo passou de 113 ofensas em 34 arquivos-base para 86 em 45 arquivos candidatos, mas possui débitos novos de métricas/estilo e é comparado com o baseline no pacote de evidências; não está aprovado integralmente.
- Build de produção Vite: tentativa com heap de 1536 MiB falhou por **JavaScript heap out of memory**, código 134. A máquina tinha aproximadamente 0,79 GiB livre de 7,84 GiB. O build completo precisa passar em CI/runner com memória suficiente.
- Não existe gate de typecheck separado configurado neste pacote; não foi declarado como aprovado.

Os testes selecionados incluem código Enterprise e concorrência real do banco; não são a suíte inteira do produto nem um E2E físico de WhatsApp. Avisos de depreciação Rails/Rack e sourcemap ausente do pacote ProseMirror foram registrados.

As três migrations pendentes da base usada no laboratório foram aplicadas somente nos bancos descartáveis de teste. O schema do checkout e os bancos produtivos não foram substituídos.

## Dependências e pendências de aceite

1. Passar build frontend completo e CI no SHA exato da candidata; concluir os débitos novos de métricas e os avisos relevantes antes da promoção.
2. Validar E2E em navegador com dois agentes, supervisor, abas abertas e transferência durante reconexão.
3. Homologar o percurso remoto Broker URA → admissão humana. Os guards da URA nativa LAB2 foram testados; a atomicidade do handoff remoto entre sistemas não foi comprovada neste incremento.
4. Homologar WhatsApp/engine e histórico completo em tarefa própria. Este incremento não altera a captura histórica nem comprova que todo o histórico do celular estará disponível.
5. Publicar traduções pt_BR dos novos rótulos pelo fluxo de tradução do repositório, que exige alterações de idioma em `en`.
6. Preparar release e ativação seletiva por caixa somente após esses gates. Nenhuma mudança deste incremento está ativa em produção.

## Compatibilidade de publicação e retorno de versão

Os campos são aditivos para clientes HTTP antigos, mas o binário antigo não aplica a nova exclusividade. Não misturar web/Sidekiq antigos e novos após ativá-la. A promoção deve primeiro colocar todos os processos no SHA aprovado, revalidar o frontend e os avisos de acesso, e somente depois permitir ativação seletiva da caixa. Voltar ao binário antigo com caixas exclusivas ativas pode reabrir a visibilidade aos colegas. Jobs novos de invalidação também não devem ficar entregues a workers antigos. Preferir correção para frente ou manter o atendimento indisponível até assegurar uma versão que aplique a mesma política; não apagar a auditoria ou as solicitações persistidas para realizar retorno de versão.
## Evidências e reprodução

O pacote externo contém logs RED/GREEN, RSpec final, Vitest, ESLint, Prettier, RuboCop baseline/candidato, tentativa de build, lista de arquivos, patch e manifesto com SHA-256. Os recursos Docker `jrc-distribution-*` são exclusivamente locais, sem números reais ou dados de clientes.

Próximo passo verificável: executar o build completo e o E2E de visibilidade no SHA desta candidata, depois validar o handoff remoto com o Broker, sem reenviar mensagens UNKNOWN.