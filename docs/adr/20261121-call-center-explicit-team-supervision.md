# Supervisão explícita das equipes nativas do Call Center

As figuras 3 e 12 exigem supervisor principal e supervisores adicionais. A equipe nativa já é compartilhada com outros módulos; selecionar seu supervisor não pode criar participação, ramal, cobertura corporativa ou permissão.

Reutilizar `Team` e `AccountUser`. A adição `TeamSupervision` armazena somente a identidade da conta, equipe, vínculo de usuário e papel principal/adicional. Não há cópia de usuário ou novo cadastro de equipe. A associação permite a mesma pessoa em várias equipes e no máximo um principal por equipe; não promove automaticamente um adicional.

A administração usa a autorização nativa: administrador com direito explícito de administrar e cobertura GROUP quando a estrutura estiver configurada. A escolha de pessoa exige autenticação ativa, elegibilidade e direito nativo de supervisão, além de cobertura atual de todos os escopos ativos da equipe. Unidade não é promovida a empresa; equipe inativa não fornece cobertura herdada. O vínculo não concede direitos novos. A supervisão continua obedecendo à política v1, inclusive o fallback nativo já existente para administrador elegível; administrar as concessões e revisar Nico exigem seus direitos próprios explícitos.

Cada atualização revalida sob o mutex nativo da conta e usa a revisão do estado real. A troca do principal e as remoções são atômicas e auditadas. Repetir uma seleção sem mudanças preserva IDs e não gera evento duplicado. O vínculo de supervisão não é fonte de permissões, não é `TeamMember` e não é participação em fila.

O popup reutiliza o Dialog existente: busca/paginação, principal/adicionais, revisão explícita, comparação em conflito, recarga do servidor e preservação do rascunho em recusa conhecida. Resposta incerta impede retry cego. Trocar conta/equipe/perfil elimina os nomes e ignora respostas anteriores.

A migration adicional é somente aditiva e sem backfill. Mantém as 11 migrations anteriores por hash. A admissão exige schema exato, FKs compostas de conta, unicidade e CHECK validado; drift é recusado. A reversão destrutiva fica bloqueada até revisão específica. As novas associações de destruição de Team/AccountUser preservam a auditoria transacional; compatibilidade Enterprise foi inspecionada e precisa da regressão nativa.

## Aceite deste incremento

- APIs autenticadas com conta/cobertura/permissões, candidatos paginados e identidades bigint exatas.
- Persistência, recarga, histórico, rejeição de revisão antiga, no-op e rollback de falha.
- Dois requests reais concorrentes: somente um aceite; nenhum grant, agente ou participação criado.
- Migration em instalação, upgrade populado e schema recarregado, mantendo todas as proteções anteriores.
- Chrome com banco sintético em desktop/celular e claro/escuro, preservando os 240 cenários anteriores e acrescentando quatro.

## Estado e limites

Preparado; validação nativa do novo SHA ainda pendente. Os 37 testes locais com transporte substituído passaram e não comprovam persistência ou homologação Chrome. O checkpoint anterior `a1a64397` foi validado separadamente e não contém esta implementação.

Este incremento não conclui toda a figura 3 ou 12: hierarquia, horários, distribuição e vínculos de filas continuam separados. Não publica configurações nem realiza comandos PABX. A revisão Nico exige seu direito próprio já implementado; o vínculo de supervisor não o concede.
