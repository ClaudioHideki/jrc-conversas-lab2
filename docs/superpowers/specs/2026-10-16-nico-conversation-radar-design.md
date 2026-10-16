# Radar determinístico do NICO

Incremento de leitura da recomendação aprovada: explicar filas com regras verificáveis, sem IA inferir abandono e sem confundir espera com SLA contratado. Reutilizar ferramentas internas do operador, sem nova aba ou executor.

Adicionar `read_conversation_radar` ao catálogo interno do NICO. Somente operador autorizado; indisponível para instruções provenientes do cliente. Serviço usa Conversations::PermissionFilterService, Account e permissões atuais, nunca a amostra de 200 conversas do assistente. Opcional inbox_id limita ainda mais o escopo autorizado.

Categorias para conversas open/pending: `waiting` tem waiting_since nativo não futuro; `waiting_alert` espera há pelo menos dez minutos; `unassigned` não possui agente humano nem AgentBot; `inactive` tem última atividade nativa (ou criação se ausente) há pelo menos 24 horas. Inatividade é uma medida de registro, não prova de abandono nem intenção do cliente. Uma conversa pode estar em mais de uma categoria. Não chamar nenhum desses limiares de SLA.

Resposta versionada com generated_at, critérios legíveis, janela de backlog ativo, total distinto e página de até 20 registros por categoria. Projeção de IDs, display_id, caixa, responsáveis, estado e tempos; sem mensagens/notas/contatos privados. Ordenação por id determinística. conversation_ids (display IDs) permitem revalidação de acesso ao histórico pelo mecanismo nativo NICO existente, sem exigir Relacionamento. Contagens são consultas atuais; não prometem um snapshot transacional do WhatsApp remoto.

Revisão: o filtro SQL Enterprise ignorava custom roles de administradores, divergindo da policy por recurso. Corrigir esse filtro compartilhado para aplicar o papel a qualquer membership; preservar acesso a todas as caixas para administrador com conversation_manage. Isso também protege projeções Customer360 que usam o mesmo filtro, sem carregar a conta inteira em Ruby para contar.

Sem bot, alterações, cadência ou envio. Reutilizar confirmação/serviços existentes para ações futuras. Revogação de acesso e dados de outro Account/caixa precisam de regressões. Sem ENV/Compose/schema ou publicação.
