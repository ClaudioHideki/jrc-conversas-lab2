# Radar NICO — validação local

Nova ferramenta interna `read_conversation_radar`, no catálogo do operador existente. Consulta o backlog ativo completo, sem o limite de 200 conversas da amostra do assistente. Categorias: espera nativa, espera de pelo menos dez minutos, sem humano/AgentBot e inatividade nativa de 24 horas. Categorias podem se sobrepor. Nenhum desses limiares representa SLA contratado ou comprovação de abandono.

Cada categoria traz total distinto, até 20 registros por página, has_more, próximo número de página e limite explícito de vinte páginas; filtrar inbox_id reduz o público. O resultado identifica geração, critérios e escopo. Não retorna conteúdo de mensagens, notas ou dados de contato. Não inicia rotina, altera registro ou envia mensagem. É consulta do NICO; não foi adicionada uma tela de radar ao Cockpit nem alterados os indicadores herdados dele.

Revisão independente encontrou dois problemas Important, ambos reproduzidos e corrigidos antes de concluir este incremento:

- O filtro Enterprise ignorava custom roles de administradores, embora a policy por conversa os restringisse. O filtro compartilhado agora aplica o papel a qualquer membership, preservando acesso de administrador com conversation_manage. Protege também as projeções Customer360 que o reutilizam.
- Referências genéricas Conversation revalidavam histórico pelo módulo Relacionamento. O radar agora registra conversation_ids nativos (display IDs), cuja revalidação existente independe de Relacionamento. Sessão permanece legível sem revogação; permissões continuam verificadas.

GREEN: **43 exemplos Rails**, incluindo sete do radar, filtro Enterprise e ações de domínio. Cobertos backlog de 206 conversas, duas páginas sem duplicação no cenário estático, Account/caixa invisíveis, custom role de administrador, revogação, origem cliente e histórico sem Relacionamento. O mapa Customer360 também passou nas sete regressões de serviço durante a rodada anterior de revisão. O filtro não promete um snapshot remoto/transacional entre páginas.

Alinhamento com a base 98a4be7: administrador nativo do Service Desk mantém leitura autorizada sem UnitMembership; administrador com papel operacional personalizado exige o grant. O teste antigo foi especializado nessa segunda condição e foi adicionado caso de administrador nativo mais revogação do módulo. Nenhuma policy do Service Desk foi modificada. Os testes anteriores de revogação de agente permanecem.

RuboCop dos novos arquivos e filtro alterado: sem infrações. Há estilos herdados nos grandes catálogos/OperatorSession; não foi feito refactor global. CI candidato recebeu os testes novos, sem execução remota ou push. Manifestações de composição serão regeneradas no fechamento consolidado. Sem migrations, Compose, ENV, imagem, deploy ou bot ativo.
