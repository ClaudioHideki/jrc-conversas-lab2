# Atendimento por caixa de origem — decisão de experiência

Data:05/11/2026. Base LAB2 `200b4f1ddd7459ec924e314cfe34cb93f11c5d5e`. Documento local de definição; não é implementação, publicação ou deploy.

## Pedido e escolha do usuário

O agente pode participar de várias caixas, pertencentes a atendentes, departamentos ou empresas diferentes. Precisa identificar por qual número o cliente entrou e por qual número sua resposta sairá. O usuário escolheu explicitamente **lista separada em grupos por caixa**, como “Lucas — Suporte” e “Ronald — Suporte”. Preservar atendimento compartilhado, roteamento via URA e permissões existentes.

## Causa da ambiguidade atual, confirmada no código

- `InboxChannelGroups.vue` agrupa por tipo de canal, como WhatsApp/email, reunindo várias inboxes num grupo.
- Esse componente passa `operational`/`show-assignee` para `ConversationCard.vue`, mas não habilita nome da caixa. O cartão operacional suprime sua seção normal de metadados e mostra o nome do responsável solto embaixo da prévia.
- `TimeAgo.vue` mostra simultaneamente idade da criação e da última atividade (`criação • atividade`), produzindo pares como “1mo • 9m”. Isso não tem a mesma semântica do horário da última mensagem do WhatsApp.
- O cabeçalho da conversa enfatiza contato/canal, sem identificação persistente da inbox e do número empresarial. O mesmo problema existe ao responder.
- A serialização atual fornece inbox_id/nome e phone_number nativo. Caixa Broker usa Channel::Api e não recebe automaticamente phone_number nativo. A resposta autorizada de health possui phoneNumber/identityApproved, mas o cache de ConnectionHistory não persiste esse número hoje. Não inferir número do nome da caixa, do telefone do cliente ou de provider_config bruto.

## Apresentação definida

1. **Grupos por inbox_id**, não pelo nome do atendente ou pelo tipo de canal. Cabeçalho com nome da caixa, empresa/setor quando explicitamente cadastrados, número de atendimento confirmado, indicador de estado da conexão e não lidas daquela caixa. Contagem carregada não pode ser apresentada como total integral.
2. Grupos recolhíveis, com preferência visual local. Conversas de cada caixa ordenadas pela última mensagem útil, usando desempate estável. Não mudar backend/membership para fazer um grupo aparecer. Não mostrar seções vazias de canais não usados.
3. Cartão: avatar/nome do cliente ou grupo; última mensagem; horário simples (hora/Ontem/data); não lidas; origem compacta quando necessária, inclusive busca/lista mesclada. Responsável tem rótulo explícito “Atendendo:”, separado da origem.
4. Conversa aberta: origem sempre visível, por exemplo “Caixa Lucas — Suporte · Operadora · WhatsApp [número]”. Campo de resposta repete “Responder pelo WhatsApp de Lucas — Suporte”. Mensagem continua vinculada à inbox real; não criar seletor que silenciosamente envie por outro número.
5. Ronald, como membro da caixa Lucas, pode atender o cliente que entrou no WhatsApp Lucas. A origem continua Lucas e o responsável pode ser Ronald. Transferir responsável/time não troca automaticamente o número remetente.
6. Mesmo cliente contatando Lucas e Ronald, ou Operadora e Construtora, mantém conversas de origem distintas. Cadastro de contato pode ser compartilhado; origem da conversa não determina propriedade exclusiva do cliente ou vendedor. Não colapsar diferentes inboxes por telefone.

## Filtros e ciclo de atendimento

- Atalhos simples: Todas, Não lidas e Conversas de grupo. Seletor de caixa quando útil. “Todas” significa todas dentro do escopo autorizado, não todas as conversas da Account.
- Manter a escolha Minhas/Minhas e compartilhadas conforme a regra atual. Em Mais filtros ficam estado, time, responsável e canal. Preservar parâmetros de URL já existentes; não trocar a consulta silenciosamente ao abrir link pendente/open/all.
- Resolver continua sendo ação operacional. Uma resolvida permanece consultável em Todas com indicador discreto; Em atendimento é recorte opcional. Filtro não é necessário para a ação de resolver existir. Histórico importado não entra como atendimento novo nem muda SLA/responsável.
- Exibir horário da última mensagem; idade de criação e SLA ficam nos detalhes/visão operacional. Não apagar os dados de SLA.
- “Não lidas” filtra mensagens não lidas; não redefinir marcador do backend ao trocar a apresentação. Lidar com paginação sem filtrar somente uma página e anunciar resultado completo.

## Contrato seguro da origem

A lista usa um objeto de origem autorizado e enxuto: inboxId, inboxName, channelKind, ownNumber, numberStatus (VERIFIED/UNKNOWN/STALE), verifiedAt e companyLabel opcional configurado. Os nomes são de apresentação; o identificador de roteamento continua inbox_id. Fonte native phone_number ou identidade Broker validada, nunca contato.phone_number.

Para Broker, implementar leitura por lote/cache revalidado, sem HTTP por conversa ou por renderização do cartão. Vincular o número à integration/instance/identityRevision atuais; resposta atrasada de identidade anterior não pode atualizar a origem. Sem confirmação ou com informação desatualizada, mostrar “Número a confirmar”/estado de atualização, preservando nome e ID corretos da caixa. Não adivinhar números nem expor credenciais, URLs de webhook, segredos ou configuração do provider.

O compositor e o backend continuam conferindo account/inbox/conversation. A etiqueta visual não autoriza envio. Desconexão e número trocado precisam aparecer, sem provocar restart, QR ou migração automática.

## Arquivos e testes da implementação seguinte

- UI: `routes/dashboard/inbox/InboxChannelGroups.vue`, `HoyaInboxWorkspace.vue`, `InboxList.vue`, `components/widgets/conversation/ConversationCard.vue`; extrair componente compartilhado de origem e apresentação de horário sem alterar todas as outras listas desnecessariamente.
- API/dados: serialização autorizada das inboxes; `JrcBroker::Response`, `ConnectionHistory`, `Control` e fonte de identidade vigente. Verificar overlay Enterprise e policies. Nome empresarial adicional deve vir de vínculo cadastrado, não de interpretação do nome da caixa.
- Regressões: duas caixas com mesmo nome; mesmo cliente em duas caixas; Ronald responsável na caixa Lucas; agente revogado; nome/número do cliente diferente do número de atendimento; origem desconhecida/desatualizada; resposta de status fora de ordem; troca de número; inbox excluída; admin versus agente/custom role; URA; unread/paginação/realtime; resolvida/history; voz/email preservados; largura pequena, teclado e leitor de tela.
- Prévia limpa: texto de origem “Saída observada” e participante LID não devem dominar a lista. Adaptar somente mensagens identificadas por metadados de origem, sem regex que remova texto legítimo de cliente e sem apagar auditoria/conteúdo persistido.

## Relação com a sincronização histórica

Este desenho complementa o plano Broker `2026-11-05-whatsapp-history-sync.md`, especialmente a jornada/apresentação. Organizar a lista não recupera o histórico ausente do celular: captura/persistência/projeção continuam necessárias. As53 atribuições antigas de bot e a definição de membros das caixas continuam decisões independentes; não as mudar silenciosamente para a interface parecer completa.

## Limite desta definição

Foram conferidos código e imagens fornecidas. Nenhum produto, dado, credencial, membro, número, campanha ou servidor foi alterado nesta rodada de desenho. Os nomes Lucas/Ronald são os exemplos informados pelo usuário; nenhum número real foi presumido ou cadastrado.
