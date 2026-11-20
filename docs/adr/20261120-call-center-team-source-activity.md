# Estado da origem de equipe somente no Call Center — 20/11/2026

Status: decisão de negócio aprovada; implementação incremental em andamento, ainda sem testes nativos deste complemento.

A inativação suspende somente a origem daquela equipe no Call Center. A elegibilidade atual é individual e não será convertida em herança. Concessões individuais, outras equipes, Team/TeamMember e os acessos de CRM, Backoffice, Aprovações e demais módulos serão preservados. Áudios institucionais terão biblioteca separada por unidade/cobertura; essa é outra frente e não inclui gravações de chamadas.

O estado será uma extensão local, vinculada à Team nativa, e não outra equipe. Ausência de estado significa comportamento legado ativo. Uma tabela própria evita mudar os atributos e hashes históricos dos AccessGrants. As revisões existentes permanecem idênticas quando não houver estado explícito; mudanças reais devem entrar na revisão esperada, inclusive para membros e fontes afetadas.

A projeção local compõe a associação nativa/proposta e exclui apenas equipes inativas da origem de permissões e cobertura do Call Center. Usa CorporateCoverage/CurrentStructureScopes existentes por adaptador local; não altera a cobertura dos outros módulos. A desativação não remove pessoas, filas, concessões ou registros históricos. Sem origem restante, não haverá fallback para concessões antigas. A configuração corporativa continua sendo determinada pelo mecanismo nativo.

A atualização usará a autoridade administrativa nativa, mutex da Account, revisão, reautorização e auditoria na mesma transação. A reativação exige conferir direitos efetivos e ampliação de cobertura para cada membro. Configure isoladamente não pode restaurar monitoria, gravações ou publicação. A perda do último agente elegível exige revisão/confirmação do gestor e auditoria, reutilizando o mecanismo atual, sem publicar no PABX.

A migração cria somente a extensão local, com FK composta de conta/equipe, unicidade e estado/revisão válidos; as seis migrations anteriores e os SQLs congelados não serão alterados. Não insere estados, não ativa contas nem concede direitos. Não executar em produção. A reversão física é bloqueada: apagar estados inativos ou executar um binário antigo que os ignore pode reativar fontes. Uma futura implantação/rollback exige procedimento próprio; a imagem e os ambientes atuais permanecem intactos.

Aceite exige provas de legado sem mudança, conta/unidade, outras equipes/concessões individuais, preservação de outros módulos, reativação sem alçada negada, concorrência PostgreSQL, revisão/auditoria atômicas, instalação/upgrade/recarga e Chrome real em1440/390 claro/escuro. Não concluir a funcionalidade apenas com estes arquivos preparatórios.
