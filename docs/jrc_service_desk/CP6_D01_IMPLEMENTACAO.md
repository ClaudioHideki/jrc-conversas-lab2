# CP6-D01 - implementacao limitada da aprovacao humana

**CANDIDATO PARA HOMOLOGAÇÃO — VALIDAÇÃO NATIVA PENDENTE**

Base unica desta continuacao: candidato CP6 anterior, SHA-256
75bf3a187e5fd98430df3148664f136177a6bf58ee18140a4511f0a1cc94e3fe.
Nenhum checkpoint foi reconstruido, nenhum patch foi reaplicado. Novo pacote: `JRC-CONVERSAS-SERVICE-DESK-CANDIDATO-HOMOLOGACAO-20260928-R2.zip`.
A execucao usa sempre o contexto nativo; zero migrations/tabelas novas e zero alteracoes
no schema, lockfiles/dependencias, flags, policies de chamados ou motor de ciclo/SLA.

## Inicializacao JRC, manual
A sessao Devise SuperAdmin ja existente mais a designacao nominativa protegida
`JRC_SERVICE_DESK_INITIALIZER_USER_IDS` identificam quem pode acessar o formulario.
Exigir tambem Account ativa e flag SD ligada. Nenhum desses requisitos e ativado pelo fluxo.
A lista e configurada pelo responsavel da instalacao somente depois de verificar a identidade
e autoridade do funcionario. Lista vazia ou malformada nega. Nenhum email/dominio prova vinculo.
Nao promover um agente a SuperAdmin por este pacote; a ferramenta destina-se a funcionarios
que ja possuem sessao administrativa nativa autorizada. Os poderes globais preexistentes do
SuperAdmin nao foram ampliados nem removidos; nao se deve confundir esta ferramenta com
revogacao desses poderes fora do Service Desk.

GET nao escreve. POST exige CSRF, selecao humana do destinatario, nomes/codigos expressos,
referencia da autorizacao e confirmacao. Uma transacao sob lock da Account cria operadora,
unidade e primeiro UnitMembership. A mesma transacao grava tres eventos Audited e um recibo
consolidado. Falha aborta o conjunto. Repetir mesma chave/conteudo/autor devolve o recibo;
outra tentativa em Account inicializada falha. A prova real de concorrencia aguarda PostgreSQL.

O funcionario nao recebe AccountUser, UnitMembership ou capacidade. E proibido usar o proprio
ator, outro SuperAdmin ou usuario designado inicializador como destinatario. O cliente deve
ser usuario confirmado e AccountUser nativo existente da mesma Account. Nenhuma role e alterada.
O redirecionamento GET consulta recibo e registros novamente; alteracao posterior e indicada,
nao escondida. O autor continua identificavel mesmo sem possuir AccountUser na Account.

O fluxo destina-se a estrutura SD vazia. Dados parciais nao sao mesclados/apagados nem se cria
unidade ficticia. Reconfiguracao de estrutura preexistente usa a autoridade explicita de
cliente, quando disponivel. Necessidades de reparacao privilegiada nao sao automatizadas.

## Administracao posterior do cliente
Quatro chaves adicionadas ao catalogo NATIVO CustomRole.permissions, sem novo RBAC:
structure_view, operator_companies_manage, units_manage, unit_memberships_manage,
todas prefixadas jrc_service_desk_. Nenhuma entra nos defaults agent/administrator, que
permanecem exatamente 23/33. A lista anterior de 33 capacidades permanece na mesma ordem.
Os tres manages exigem structure_view. Exigir tambem AccountUser administrator, role nativo
valido da Account, flag e inicializacao existente. As chaves sao explicitas e de ESCOPO
ESTRUTURAL DA ACCOUNT; nenhuma exige ou concede tickets_view/module_view.

A pagina `/app/accounts/:accountId/service-desk-structure` usa o layout/dashboard nativo,
componentes nativos e contexto proprio SEM provider operacional. Ela lista/cria/edita/
ativa/desativa operadoras, unidades e memberships. Nao existe DELETE; identidades/codigos/
proprietarios sao imutaveis. Ausencia do CustomRoles nativo bloqueia a delegacao granular,
sem criar sistema substituto nem habilitar a feature de CustomRoles automaticamente.

Conceder/reativar escopo a si proprio e negado. Revogacao propria pode ser explicita.
Team nao concede unidade. Configurar estrutura nao modifica capacidade operacional do ator
ou destinatario. Admin sem UnitMembership continua sem chamados, mesmo gerenciando estrutura.
A revogacao da capacidade estrutural invalida inclusive replays; revogar UnitMembership tira
a operacao, nao as capacidades estruturais expressamente concedidas. Para revogar ambas,
revogar ambos os direitos; nao excluir role supondo revogacao (o fallback nativo foi preservado).

## Resposta, auditoria e consistencia
Consultas paginadas e escopadas por Account. Writes rejeitam account_id/role/capacidades e
FKs fora da Account; backend verifica todas as referencias. Revisao por digest e chave
idempotente; lock Account -> ator/AccountUser/CustomRole -> recursos, compatibilizando a
ordem dos comandos operacionais. Auditoria Audited::Audit, associada aos objetos SD e nao a
Account.associated_audits. Autor, Account, Unidade quando existente, motivo e before/after.
Nenhuma garantia contra SQL privilegiado ou retencao externa de auditoria e declarada.

Frontend: POST/PATCH -> GET recibo -> GET registro -> comparacao -> nova listagem -> F5.
Erro de leitura apos escrita e confirmacao pendente; nao ha contador local, localStorage,
dados de demonstracao ou mensagem de sucesso sem releitura. Estado e limpo ao trocar Account/
usuario/flag; revalidacao no foco/visibilidade e a cada60s, nao push instantaneo. A API verifica
novamente a cada requisicao. Revalidacao bem-sucedida da MESMA autoridade preserva o
rascunho; identidade, capacidades ou negativa novas descartam o estado protegido. Arquivos/contatos/mensagens/chamados/KPIs nao sao consultados pela
pagina estrutural. KPIs operacionais continuam no scope original.

## Limites desta entrega
CP6-D01 aprovada e implementada; nenhum CP6-D02 pendente. Identidades e capacidades reais
precisam de configuracao humana no destino. Nao implementados: Projetos, portal, anexos,
resposta de canal, cadastro mestre de calendario, integracoes ou outro checkpoint.

**PENDENTE — validação nativa em Docker/servidor**
