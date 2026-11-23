# Escopo prospectivo das automações de encerramento

Status: incremento interno em validação nativa. Não ativa regras nem executa destinos.

As automações devem usar as permissões atuais do agente original e a origem real do atendimento. A empresa/unidade atual de uma fila não prova a origem de uma chamada antiga. Retirar e restaurar um vínculo também não pode reativar uma autorização histórica implicitamente.

Acrescentamos um registro imutável do vínculo entre a fila operacional e a empresa/unidade corporativa já cadastradas. Os gatilhos capturam alterações relevantes da fila, da unidade operacional, da empresa emissora e da unidade de negócio. Estados sem mapeamento ou inválidos são registrados sem conceder acesso. O conteúdo contém somente identificadores tipados, estado e hashes; não copia as configurações completas da unidade.

A atualização do banco cria uma primeira observação no momento real da instalação. Não inventa versões anteriores, não altera chamadas, catálogos, formulários, permissões ou usuários. Uma consulta anterior à primeira observação retorna ausência de evidência. O registro acrescentado usa nomes SQL próprios e recibo separado, preservando os 14 históricos já publicados. Reexecução verifica o recibo; não recompõe uma estrutura divergente silenciosamente.

O registro é uma evidência, nunca uma concessão. A configuração e cada execução futura ainda precisarão de autorização nativa atual, versão imutável da regra, confirmação do motivo para ações antecipadas, finalização real para ações após ACW e recibos independentes e atômicos dos destinos. Nada disso é substituído por uma linha no histórico de escopo.

Neste incremento não existe ativação, endpoint de automação, job de destino, credencial de serviço ou chamada externa. A decisão sobre desativação de ações pendentes permanece separada. Os adaptadores de CRM, Service Desk e notificações ainda precisam reutilizar suas autoridades nativas; não serão habilitados por suposição.

Validação exigida: instalação sobre filas/chamadas preenchidas, reexecução, recarga do schema, alterações A → B → A, mapeamentos malformados/entre contas, remoção nativa da fila, imutabilidade, preservação dos recibos anteriores e concorrência PostgreSQL real. Os testes locais de leitores e hashes não equivalem a essa execução.

## Correção de concorrência antes da primeira homologação

O histórico não pode acrescentar um bloqueio `KEY SHARE` tardio à linha nativa de Account em cada revisão. A CI c0c47932 reproduziu interferência no teste legado de mudança de unidade e no novo cenário de emissora/fila.

A referência técnica contém somente o identificador da conta real, com PK/FK, sem gerar contas, pessoas, conexões ou permissões. O caminho declarativo passa a ser histórico → referência imutável → Account. A FK da fila e sua nulificação histórica permanecem. A referência só pode ser apagada pela remoção real da conta; reparenting é rejeitado. O recibo estrito inclui ambas as tabelas e os gatilhos próprios da conta, sem alterar as 14 migrations anteriores ou o lock nativo de autorização.

Trata-se de correção da 15ª migration candidata, nunca implantada, ainda sem aceite. Um schema de protótipo divergente continua bloqueado, sem conversão automática de dados. São obrigatórios instalação, atualização preenchida, recarga, reexecução, isolamento, imutabilidade, cascata real e concorrência nativa, mantendo o teste legado intacto.
