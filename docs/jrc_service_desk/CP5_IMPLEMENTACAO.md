# CP5 - integracao nativa

**CP5 IMPLEMENTADO PARA REVISÃO — VALIDAÇÃO NATIVA ACUMULADA PENDENTE**

PENDENTE — validação nativa em ambiente Docker/local

## Continuidade e decisoes

Base unica: JRC-CONVERSAS-SERVICE-DESK-CP4-CONSOLIDADO-20260928.zip.
SHA-256 verificado antes da extracao/alteracao:
6365d93606933d7109e59c924b41b3eaadb5b52b356c951c0cb1cd37e7071c21.
Registro: 28/09/2026. Sem reconstruir checkpoints, reaplicar patches ou retornar ao ZIP
original. SD-D01..SD-D05, CP2-D01/D02 e CP4-D01 preservadas. Nenhuma nova decisao humana
CP5-Dxx ficou pendente. CP6 e Projetos NAO iniciados.

## Arquitetura nativa

33 capacidades de acao foram acrescentadas ao catalogo CustomRole.permissions existente.
Os seis valores anteriores e seu editor foram preservados. Nao ha nova tabela de roles,
permissoes em UnitMembership, login alternativo, agent duplicado, RLS ou flags novas.

Capabilities interpreta os dois perfis nativos e CustomRole. Os defaults de agent e
administrator sao listas explicitamente enumeradas; nao ha wildcard. CustomRole substitui
integralmente defaults, mesmo quando AccountUser.role=administrator. Roles customizados
anteriores sem permissoes Service Desk continuam sem acesso ao modulo.

AccountUser e o contexto autenticado continuam a fonte de identidade. Em cada comando/policy,
Account, User e AccountUser sao reconferidos; CustomRole estrangeiro ou invalido nao vira
um papel padrao. Acesso final depende de feature, Account, unidade ativa, operadora ativa,
UnitMembership ativo, permissao da acao e policy. Regras de ciclo continuam adicionais.

Sem tickets_view_all, a visibilidade e autoria/atribuicao/equipe DENTRO da unidade vinculada.
Com essa capacidade, abrange apenas as unidades vinculadas. Team nao concede unidade.
AccountUser responsavel precisa ter tickets_view e UnitMembership ativo no mesmo escopo.

## Granularidade e comandos

Editar dados nao concede mudar prioridade: o PATCH verifica a capacidade de cada campo
antes de salvar. Atribuir e transferir possuem capacidades diferentes. TransferTicketService
reutiliza a transacao do comando existente, mas usa transfer? e ticket_transferred; nao
transfere unidade. A rota /transfer nao e mais um alias de tickets#assign.

Criacao com atribuicao exige tickets_assign; com conversa exige conversations_link e
ConversationPolicy nativa. Essas condicoes tambem sao revalidadas ao reapresentar uma
chave idempotente: uma chave guardada nao concede permissao revogada.

LifecycleActionPolicy verifica cada acao e filtra as opcoes. Revogar resolve impede replay
dessa transicao, mesmo que outra capacidade de ciclo continue. Publicacao exige
lifecycle_policies_manage e unidade; nenhuma nova versao retargeta chamados existentes.
Selector, regras, calendario, snapshots e motor de clocks do CP4-D01 permanecem intactos.

Notas, historico, SLA, cliente, conversas e condicoes contratuais brutas possuem gates
separados. Eventos de vinculo ocultam os identificadores da conversa quando sua ACL nativa
ou a capacidade de conversa foi revogada. Ler prazo nao concede condicoes financeiras.

As mutacoes continuam transacionais. Os locks existentes de identidade/unidade passaram
a proteger tambem a linha do CustomRole nativo do autor e do responsavel quando aplicavel.
Isso nao e uma prova SQL de ausencia de races/deadlocks; concorrencia real fica pendente.

## Integracoes com o JRC

CustomerContextService retorna somente identificadores, Account e nome do Contact nativo e,
quando instalado, sua Company nativa, depois de scoping e Pundit. Nao cria clientes ou
empresas, nao converte Company em operadora e nao usa fallback silencioso para Organization.
Quando a associacao nao existe, retorna not_available; sem vinculo, not_linked.

ConversationNavigationService reautoriza chamado, vinculo e conversa na Account atual.
Retorna a rota nativa inbox_conversation com conversation_id=display_id; a PK do banco fica
separada. O frontend valida escopo/IDs/nome da rota e nao encaminha URLs arbitrarias. O
modulo nativo continua aplicando sua propria autorizacao ao abrir. Nao se copiam mensagens,
nao se cria conversa e nao se simula envio de mensagem ou chamada.

Os lookups continuam usando AccountUser, User, Team, TeamMember e Contact. Projecoes de
nomes nativos reconferem Account e policies. Company aparece somente como cliente.

## Navegacao, contexto e estado

Sidebar nativa so revela o modulo com contexto afirmativo do backend. Flag false nao
consulta API operacional. O destino inicial depende das telas permitidas; nao e sempre
dashboard. Guards atualizam a Account de destino e consultam ui_context. A pagina de acesso
negado/erro nao contem registros e retorna ao JRC nativo, sem segunda autenticacao.

Breadcrumb nativo, voltar para lista, detalhes e configuracoes foram integrados. Tabs e
botoes dependem das capacidades recebidas. Rascunhos/dados sao apagados em troca de
Account/usuario/flag, negativa da API e nova projecao de autorizacao. Geracoes impedem que
respostas antigas preencham outro contexto.

A interface revalida ao foco/visibilidade e a cada 60 segundos; nao ha storage persistente
ou cache de permissao como fonte de verdade. Revogacao remota NAO e um evento push instantaneo:
a projecao visivel pode durar ate o proximo ciclo, mas cada API/action revalida no backend.
Falha de verificacao nao reaproveita contexto antigo como se ainda fosse autorizado.

## Indicadores

TicketQuery, KpiCounts e matematica SQL foram preservados. Dashboard requer sua capacidade
propria e o mesmo TicketPolicy::Scope da listagem. Usuarios com escopos diferentes podem
ter totais diferentes. Total=sum(open,waiting,resolved,closed,cancelled); ativos=open+waiting.
Nao existe contador novo hardcoded, incremento otimista ou grafico demonstrativo.

## Auditoria

Eventos existentes mantem autor/membership, Account, unidade e timestamp. Transicoes e
publicacoes mantem versao/digest. Transferencia recebe evento especifico.

Mudancas de permissoes SD em CustomRole geram audit na tabela nativa audits, com Current.user,
Account e antes/depois. Quando nao houver ator autenticado, ele nao e inventado. A alteracao
de custom_role_id tambem entra na auditoria nativa AccountUser. Mudancas de permissoes
legadas sem delta SD nao geram esse audit adicional. Falha do audit interrompe a mutacao.

Essa auditoria tem escopo Account, pois o papel pode afetar varias unidades; nao inventa
uma unidade nem persiste outro RBAC. Readonly de dominio nao protege de SQL privilegiado.

## Limites de compatibilidade

Nenhuma migration foi criada/aplicada e nenhuma tabela/coluna ou schema alterado. Flags,
lockfiles, requisitos, jobs, SLA de Conversas e os demais modulos permanecem preservados.
Mudancas fora dos arquivos SD sao pontuais: sidebar, editor/labels nativos de CustomRole,
seu catalogo/auditoria, campo auditado de AccountUser e registro das rotas SD.

A exclusao NATIVA de CustomRole continua anulando custom_role_id e restaurando o perfil
nativo base. Nao usar exclusao de role como revogacao SD. Para revogar, retirar UnitMembership,
atribuir papel sem capacidades SD ou desligar a feature. Reescrever a exclusao global
alteraria comportamento de outros modulos. O modal nativo tambem depende da extensao/feature
CustomRoles existente; nao a habilitamos nem criamos armazenamento alternativo.

A UI de configuracoes de filas/categorias/prioridades/status segue leitura. Policies e
capacidades especificas nao tornam seu CRUD completo. Bootstrap de operadora/unidade/
membership, anexos, comunicacao, portal, relatorios completos, governanca e ferramentas
NICO/automacoes ainda nao expostos continuam PENDENTE, sem sucesso falso.

Lookups e vinculos com avaliacao Pundit por registro podem materializar resultados antes
da paginacao para nao revelar totais proibidos. As novas verificacoes geram consultas
adicionais. Desempenho/concorrencia/merge/exclusao nativos devem ser medidos, nao presumidos.

## Testes e evidencias

Novos testes isolados Ruby: 11/804 de capacidades e 6/91 da TicketPolicy/Scope real, usando
repositorio e contexto sinteticos. O segundo NAO testa autenticacao nativa ou SQL.
Node CP5: 71 casos sobre clientes, decoders, guards e sessoes reais, sem montar Vue.

Regressao isolada CP4: 24/166, 9/40 e 8/186 em tres arquivos Ruby e 198 casos Node anteriores
(100 CP3 + 57 CP4 + 41 ciclo). Todas as execucoes finais sem falhas.

Foram escritos seis arquivos RSpec novos e dois specs Vitest novos; nao executados
nativamente. Um helper JS compartilhado e dois testes Ruby isolados completam a cobertura
nova. Fixtures sao exclusivas de testes e nao entram na aplicacao.

Tres arquivos de teste anteriores receberam adaptacao pontual, sem remover exemplos:
fixtures.js, cp4Cases.js e routing.spec.js. Foram acrescentadas capacidades explicitas e
o transporte do ui_context ao roteador; os 198 casos anteriores continuam passando
isoladamente. Os demais testes anteriores ficaram byte a byte preservados.

A revisao estatica corrigiu uma referencia a shared context inexistente nos specs novos,
substituindo-a pelo modulo de fixture que a base realmente fornece. Nao houve teste nativo
reprovado ocultado: as suites nativas nao puderam iniciar.

Parsing/sintaxe/imports nao equivalem a Vue compilado, lint ou build. Os roteiros anteriores
CP1..CP4 permanecem com validacao pendente. CP6 e Projetos nao foram iniciados.
