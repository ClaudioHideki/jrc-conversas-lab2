# Call Center: elegibilidade explícita e herança por equipe nativa

Status: contrato aditivo preparado antes da implementação, 17/11/2026.
Base: checkpoint a3355707 e proteção incremental de fallback.

## Requisitos e fontes

Word Parte 1, Figura 11: não ativar Call Center ao criar usuário; distinguir
origem herdada, individual e efetiva; não conceder acima da própria alçada.
Figura 12: equipe, participação e supervisão são conceitos distintos. Não
duplicar usuários, equipes nem cobertura corporativa.

## Persistência e compatibilidade

Adicionar uma configuração AccessGrant vinculada por FK ao AccountUser ou
Team nativo, exclusivamente um dos dois. Não é cadastro paralelo de usuários
ou equipes: cada sujeito nativo tem no máximo uma configuração. Para usuário,
armazenar elegibilidade default false e capacidades concedidas/bloqueadas;
para equipe, somente capacidades herdáveis. Não adicionar campos funcionais
genéricos ao AccountUser nem ao Team compartilhados com os demais módulos.
Não alterar permissões funcionais dos demais módulos, presença, distribuição
ou associação à conta. As listas aceitam somente as capacidades CC já
registradas; novas capacidades exigem extensão específica posterior.

A migration marca elegíveis somente os vínculos existentes na execução do
upgrade, preservando o comportamento anterior sem aumentar capacidades.
Vínculo sem configuração começa pendente mesmo se administrador, membro de equipe ou
portador de perfil. Reexecutar a migration não reativa usuários suspensos.
Não inferir elegibilidade por nome, cargo, presença ou timestamp inventado.

## Precedência e escopo

1. Conta ativa, feature, vínculo pertencente à conta e elegibilidade são
   condições obrigatórias; falha em qualquer condição nega o módulo.
2. Bloqueios individuais explícitos prevalecem sobre perfil, equipe e legado.
3. Concessões individuais, perfil nativo e equipes da mesma conta formam a
   união funcional. Ausência de checkbox não equivale a bloqueio explícito.
4. Dependências existentes permanecem: visualizar antes das operações e
   visualizar gravações antes de ouvir/baixar. Bloquear configurar não pode
   ser contornado por administrar; bloquear relatório prevalece sobre o
   alias de supervisão.
5. O resultado funcional não cria cobertura de empresa/unidade, acesso a
   carteira ou participação em fila. AccessScope e OrganizationalScope
   continuam aplicados em cada API de dados e operação.
6. Equipes removidas deixam de conceder imediatamente, mesmo que a limpeza
   assíncrona dos TeamMembers ainda não tenha ocorrido.

## Escrita, concorrência e histórico

Novas APIs setoriais editam somente os campos CC dos modelos nativos. Exigem
administrar CC e papel administrativo nativo; quando há estrutura corporativa,
exigem cobertura GROUP para mudanças de efeito na conta inteira. Não criar
grants corporativos. Recarregar ator e alvo sob lock da conta e do registro,
exigir revisão esperada e comparar capacidades efetivas com GrantGuard.
Remover um bloqueio também é uma concessão quando aumenta o resultado.

Alterar membros de equipe pelo fluxo nativo não pode conceder capacidades
latentes acima do ator. Preservar os contratos antigos e negar somente o
acréscimo CC não autorizado. Toda alteração setorial grava antes/depois,
ator e correlação na auditoria nativa, dentro da mesma transação.

## Interface e validação exigida

Reutilizar a área Permissões e o Dialog nativo, com seletores Perfil, Equipe
e Usuário; listar por pesquisa/paginação, editar em popup e mostrar fontes,
pendência de elegibilidade, diferenças e permissões efetivas. Não ativar
todos nem incluir capacidades críticas por conveniência. Conflitos retêm o
rascunho e exigem recarga/revisão explícita.

Migration: criar somente a tabela de configuração e inserir elegibilidade
compatível para os vínculos existentes, com ON CONFLICT DO NOTHING. FKs dos
sujeitos removem a configuração ao excluir o sujeito; auditoria nativa não
é apagada. Instalação sintética, upgrade populado, reexecução preservando
suspensões, defaults novos, constraints e recarga de schema. Fixtures CC
antigas devem declarar elegibilidade sintética de forma explícita; testes
das APIs nativas comprovam que usuários novos permanecem pendentes.

Rails: precedência, dependências, conta/empresa/unidade, herança por múltiplas
equipes, remoção, associação externa inválida, concessão acima da alçada,
revisão, rollback e auditoria. Vue e Chrome: usuário/equipe, criação nativa
seguida de pendência, persistência/recarga, acesso negado, conflito, desktop
1440 e mobile 390, claro/escuro. Não declarar F11/F12 concluídas sem evidência.

Este documento não ativa regras de retorno de pausas, não executa PABX e não
resolve contratos externos, limites operacionais ou figuras posteriores.

## Primeiro resultado nativo e correções

CI 44144695844 no SHA a55fdbe2 aprovou os gates históricos e a migration,
carregou o schema migrado em outro banco sintético e executou 584 exemplos
Rails (583 aprovados, uma falha, zero pendências/erros externos). O único
cenário falho foi a gravação PABX com papel explícito, mas sem elegibilidade.
Declarar a autorização sintética nesse teste mantém todas as verificações
de reprodução, download e ramal. Não ativar pessoas por atribuir um perfil.

As infrações de lint foram tratadas por separação de validações, nome claro
inherited_permissions e alinhamento. A única alteração no arquivo da nova
migration é <<~SQL.squish: SQL e versão preservados; novo hash revisado
85fa579036a807b2d50ae3c30af64b061ba9ea6c6ffe173b4e0f33d4ad922dbe.
O gate continua recusando qualquer mudança histórica ou adição desconhecida.
Nova execução do SHA corrigido é obrigatória. Interface ainda em preparação.


## Continuação: vínculo operacional e revisão do schema

A elegibilidade explícita também é conferida ao cadastrar/reativar vínculos de
fila. Usuário pendente aparece identificado e indisponível no seletor; presença
online não concede autorização, e estar offline não impede a configuração
administrativa de um usuário elegível. A desativação de vínculo existente
continua permitida após revogação. O servidor revalida após a espera por locks,
e o popup conserva o rascunho em uma revogação concorrente. Seis casos API,
um Vue e quatro Chrome preparados para o próximo SHA, ainda não aprovados.

O schema gerado pelo PostgreSQL da CI 44153428753 possui 2.194 linhas de diff
contra o schema versionado, incluindo tabelas históricas de outros módulos e
representações de constraints. Não copiar esse dump integralmente nem alterar
o gate para aceitá-lo automaticamente. Artefato/hash e decisão constam na
matriz; a recarga do dump migrado em banco sintético separado foi executada.
A conciliação histórica do arquivo versionado não é apresentada como concluída.


## Evidência 48c2a9a4 e correção do popup

CI 44159560428: 590 Rails principais + 8 concorrentes, 220 Vue e lints
aprovados. Artefato 14363849571, SHA-256
c534b23d7057543f2e4a3de1aa8ac02bf640fe15ca9c974a068a0daa1a6781d1.
Os 68 Chrome anteriores passaram; os 12 novos esgotaram 90 segundos cada
por controles fora do viewport. Não foi falha de PostgreSQL ou de bootstrap.
Usar contained no Dialog nativo do chamador para rolagem interna e footer
acessível. Acrescentar limites geométricos reais e preservar todos os cliques,
cenários e timeouts; nenhum force click ou supressão. Próximo SHA deve
comprovar o ajuste e os quatro novos cenários de elegibilidade de fila.


## Compatibilidade corporativa do destinatário

A inspeção do vínculo identificou que o ator precisava enxergar a fila, mas a
elegibilidade do destinatário não comprovava cobertura da unidade. A alçada
GROUP do administrador não é transferível. A gravação agora usa o
OrganizationalScope nativo do AccountUser destinatário, dentro da segunda
validação após os locks. Sem estrutura corporativa configurada, preserva o
contrato nativo; com estrutura configurada, exige cobertura existente de
unidade/empresa/GROUP, sem criar vínculos corporativos ou permissões.

A desativação do mesmo vínculo permanece possível após revogação. Trocar o
destinatário ou reativar exige novamente escopo válido; supervisão não
contorna a regra. O popup conserva seleções e identifica os dois campos em
português. Oito exemplos API, um caso HTTP com espera real de lock e um Vue
adicional estão preparados. Os quatro cenários Chrome existentes ganham a
prova de destinatário restrito, sem remoção de asserções nem comandos PABX.
Os dados sintéticos de sucesso passam a declarar sua cobertura expressamente.
Execução nativa deste incremento ainda pendente; não atribuir evidências do
SHA anterior ao novo comportamento.


## Origem nominal da herança

O detalhe autorizado de usuário informa o perfil nativo associado e as equipes
reais que contribuem para cada capacidade. A listagem paginada conserva seu
payload anterior; o detalhe não cria nem altera grants. A consulta continua
restrita à conta, associação nativa e autorização administrativa/GROUP. Equipe
externa, mesmo vinculada por registro malformado, não é fonte. Não são
expostos dados de auditoria a quem não possui a capacidade correspondente.

O popup distingue origem de equipe, concessão individual, bloqueio e direito
efetivo. Nomes são escapados pelo Vue. Usuário pendente continua pendente;
nenhuma inferência de elegibilidade ou participação deriva do texto exibido.
Dois casos de serviço, um API, um Vue e extensão dos quatro casos Chrome
existentes estão preparados; o próximo SHA exige validação nativa própria.


## Revalidação da disponibilidade após espera

A revisão dos consumidores de elegibilidade encontrou autorização HTTP anterior
a um lock de conta, sem nova conferência em AgentStateManager#transition. O
serviço passa a revalidar o operador dentro de AuthorityTransaction e do lock
do vínculo, sem cache de consultas. A validação da fila também ocorre nesse
ponto. Mantém idempotência, revisão de estado, rollback de projeção de ACW e
sincronização nativa. Nenhum comando ou endpoint do fornecedor é introduzido.

O registro de eventos recebidos permanece independente: revogar o operador
não apaga o histórico confirmado. AgentStateSnapshot exige autorização atual
para elegibilidade de distribuição; confirmação do fornecedor não é grant.
Cinco exemplos de serviço e três HTTP concorrentes reais estão preparados.
Os cenários válidos antigos passam a declarar a feature de teste necessária;
nenhuma asserção é removida. O adapter positivo do teste é simulado e não
constitui homologação PABX. Nova execução nativa obrigatória.
