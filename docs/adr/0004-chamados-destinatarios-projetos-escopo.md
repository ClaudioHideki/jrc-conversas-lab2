# ADR 0004: Destinatários de chamados e acesso aos projetos

- Status: Aceita para implementação por solicitação do usuário
- Data: 2026-11-17

## Contexto

A abertura interna simplificada não oferecia destinatário. Agentes habilitados
em Projetos não podiam criar por padrão e a visibilidade `account` permitia ler
projetos sem participação. O indicador Resolvidos excluía os que já estavam
encerrados; a lista principal misturava fases operacionais e terminais.
O usuário confirmou que projeto próprio inclui responsável ou participante.

## Decisão

- Reutilizar empresas operadoras, unidades e memberships existentes. A abertura
  interna oferece pessoas elegíveis na fila/equipe configurada da unidade, sem
  expor e-mails do diretório ou conceder a permissão geral de reatribuição.
  O servidor revalida conta, unidade, permissão e equipe; conserva identidade
  autenticada, observador e idempotência. A escolha explícita entra no fingerprint.
- Agentes habilitados no módulo podem criar projetos por padrão. Uma negação
  individual explícita e as restrições de CustomRole continuam prevalecendo.
- Listagens, indicadores, detalhe e consumidores do escopo de Projetos aplicam
  responsável ou participante. Administradores nativos veem a conta inteira.
  `visibility=account` permanece como dado legado sem conceder acesso a terceiros.
- A lista principal de chamados usa as fases open/waiting. Um popup paginado
  acessa resolved/closed/cancelled pelo mesmo escopo autorizado da API.
  Resolvidos soma resolved+closed; o clique usa o filtro finished correspondente.
  Os cartões da lista mantêm os filtros de empresa, unidade, texto e responsável,
  mas removem fase/status para não zerar os outros indicadores ao selecionar um.
  Aguardando usa a fase waiting e é recarregado após mutações confirmadas.

## Consequências e validação

Base funcional: imagem publicada do SHA `d468beb8744856c4bcaa972ecde4d885b60ee432`,
preservando popup de propostas, retirada de filtros de segmento e atualizações
de mensagens/histórico. Sem migration nova ou mudança de dados existentes.
Regressões cobrem persistência/replay do destinatário, rejeição de destino fora
do domínio, criação com negação explícita, isolamento e revogação de participação,
contagens por transições reais e interação com os componentes Vue.
O build desta branch exige o gate Projetos e Portal aprovado no mesmo SHA.
Publicação de imagem e implantação são etapas distintas; esta tarefa não autoriza
implantação em produção nem envio real de mensagens.
