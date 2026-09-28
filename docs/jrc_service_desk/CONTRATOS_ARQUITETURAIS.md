# Service Desk - contratos arquiteturais para etapas futuras

Documento normativo. Estes contratos delimitam interfaces e responsabilidades; NAO implementam
APIs, tabelas, jobs, eventos operacionais, modelos de chamados, calendarios ou Projetos.
SD-D01 a SD-D05 foram APROVADAS explicitamente no CP1-R2: ver `DECISOES_APROVADAS.md`.
O historico anterior esta em `DECISOES_PENDENTES.md`. As escolhas abaixo sao contratos
conceituais, nao implementacoes. CP2 e todas as etapas seguintes continuam NAO AUTORIZADOS.

## Identidade do dominio e carregamento

Dominio Ruby: `::JrcServiceDesk`; diretorios `jrc_service_desk`; prefixo de tabela
`jrc_service_desk_`. Controllers: `Api::V1::Accounts::JrcServiceDesk`. Componentes futuros
poderao ficar no diretorio frontend `serviceDesk`, distinto de `jrcService`.
Reservar `jrc_projects` para o modulo posterior, sem criar implementacao compartilhada especulativa.
Sempre usar `::JrcServiceDesk` ao referenciar o dominio dentro do namespace de controllers,
para evitar resolucao relativa para `Api::V1::Accounts::JrcServiceDesk`.
O Rails/autoloader deve resolver essas classes sem engines, inflections ou outro framework novo.

## Account, autenticacao e autorizacao

- Tenant dos documentos corresponde ao `Account` nativo. Nenhum `Tenant` novo.
- Resolver autenticacao e Account nos helpers existentes. Nao usar `params[:account_id]`
  ou `params[:user_id]` como prova de acesso. Request params nunca formam um contexto confiavel.
- Contexto Pundit: `{ user: Current.user, account: Current.account, account_user: Current.account_user }`.
- Disponibilidade e escopo da conta sao pre-requisitos; so uma policy concreta aprovada pode conceder acao.
- Sem inferir cliente autenticado a partir de um Contact, telefone, e-mail ou ID numerico recebido.
- Queries partem do escopo de Account autorizado; validar que todos os relacionamentos pertencem
  a mesma conta. ID global, display_id e ID externo devem ter semantica declarada.
- Sem default_scope global para mascarar lacunas. Sem `unscoped` ou bypass administrativo na operacao.
- APIs de lista exigem autorizacao de acao e policy_scope; actions de registro exigem policy concreta.
- Empresas/unidades/filas/equipes/participacao/propriedade e campos sensiveis acrescentam restricoes,
  nunca ampliam silenciosamente a conta. Seguir SD-D01/SD-D05 aprovadas; detalhamento de
  filtros e concessoes somente no checkpoint autorizado, com negacao por padrao.
- ACL se aplica a leitura, escrita, contagens, dashboard, pesquisa, exportacao, arquivos, eventos,
  jobs e ferramentas NICO, nao apenas a componentes e botoes.
- Futuras mutacoes exigem validacao server-side, transacao adequada, controle de concorrencia,
  idempotencia e trilha auditavel. Nenhuma mutacao existe neste checkpoint.

## Fonte unica e dependencias de outros modulos

| Responsabilidade | Contrato |
|---|---|
| Pessoas | Reutilizar User/AccountUser; Contact e solicitante/cliente, nao necessariamente login |
| Empresas-clientes | Contact/Company mantem suas funcoes nativas; JrcCrm::Organization preserva o CRM; manter tipo e ID |
| Empresas operadoras/unidades | Multiplas por Account, conceitualmente separadas dos clientes; nao reutilizar Company/Organization como operadora |
| Equipes | Reutilizar Team/TeamMember; fila de atendimento nao substitui fila de voz |
| Contratos | Fonte externa canonica + snapshots locais versionados de SLA/cobertura/franquias/condicoes; nao criar ERP |
| Conversas | Vincular Conversation/Message autorizadas; nao copiar conversas nem criar outro envio |
| Chamados | Futuro dominio operacional proprio; nao renomear Conversation para Ticket |
| Calling | Referenciar chamada/gravacao somente com acesso especifico; softphone e provedores intactos |
| CRM/Campanhas | Consumir contratos/eventos explicitos; nao alterar workflows ou aprovacoes existentes |
| Conhecimento | Reutilizar Article/Portal com protecao de conteudo interno; nao publicar artigo privado por padrao |
| NICO | Usar autorizacao, allowlist de ferramentas e confirmacoes atuais; nao criar outro Brain paralelo |
| Projetos | Integracao por vinculo/evento posterior; independencia dos modulos e flags; nada implementado |

Nao importar arquivos completos dos pacotes auxiliares como substitutos da base central.
Os pacotes Service Desk fornecem especificacao/imagens, nao uma implementacao de models/APIs.

## Persistencia e arquivos

Models operacionais futuros herdam `JrcServiceDesk::Base`. Migrations, somente depois de
aprovado o checkpoint operacional correspondente, devem incluir account_id e referencias/indices coerentes,
sem reescrever tabelas nativas. Nao determinar agora o schema de company_id/unit_id/contract_id.
Somente uma fonte por entidade; lista/workspace/dashboard devem ler a mesma persistencia.

Usar Active Storage existente. Nao reutilizar o model Attachment dependente de Message como
se fosse um documento generico. Download/upload deve validar conta, registro e visibilidade;
URL assinada nao substitui autorizacao de negocio. Scanner, retencao e compartilhamento serao
avaliados no checkpoint adequado, sem dependencias novas agora.

## Calendario/SLA

Interface conceitual futura: contexto autorizado + instante inicial + politica/versionamento +
calendario/fuso + duracao/pausas -> prazo/calculo explicavel. Primeira resposta e resolucao
sao compromissos distintos. SD-D04 aprova calendario proprio do Service Desk por Account,
com possibilidade de calendarios por operadora/unidade. Suportar horario comercial, timezone,
dias uteis, feriados, excecoes, precedencia e snapshots/versionamento de condicoes usadas.
A prioridade exata das regras, defaults, persistencia e calculos serao detalhados posteriormente.
Nao confundir a aprovacao da propriedade do calendario com definicao de toda regra temporal.
Nao invocar automaticamente o calculador de inbox para um chamado com varios canais.
Nao alterar SLA de conversas para satisfazer SLA de chamados.

## Contratos externos e snapshots (SD-D02 aprovada)

A integracao futura consultara a fonte contratual externa autorizada. O snapshot local guarda
somente condicoes necessarias e sua rastreabilidade/versao, preservando o historico aplicado
a cada chamado/calculo. Mudanca na fonte nao reescreve silenciosamente snapshots utilizados.
Nao criar ERP, provedor ficticio, cliente HTTP ou tabelas contratuais neste checkpoint.
Fornecedor, identificadores, indisponibilidade e atualizacao dependem de detalhamento futuro.

## Identidade futura do portal (SD-D03 aprovada)

Identidade dedicada vinculada ao Contact nativo; preparar conceitualmente federacao/SSO futuro.
Nao utilizar sessao interna de agente como autenticacao de cliente nem a presenca de Contact
como prova de login. Sessoes externas, endpoints publicos, SSO, impersonacao e regras detalhadas
nao sao implementados no CP1. Reutilizar autorizacao nativa compativel, nao RBAC paralelo.

## Prevalencia das permissoes (SD-D05 aprovada)

A matriz especifica do Service Desk prevalece sobre descricoes genericas. Menor privilegio;
na duvida, NEGAR. Restringir especialmente Automacoes, Configuracoes, Contratos, Pesquisas,
Portal, Ativos, publicacao de Conhecimento e informacoes financeiras. Uso/consulta nao e
administracao nem permissao de campos sensiveis. Aplicar a mesma restricao na API/backend.
A base CP1 continua negando todas as acoes: nenhuma concessao nasce deste documento.
Detalhamento e extensao compativel de permissoes nativas somente em etapa autorizada.

## APIs/frontend e observabilidade

Prefixo HTTP previsto pela auditoria: `/api/v1/accounts/:account_id/service_desk`.
Sua futura declaracao devera mapear explicitamente para `module: :jrc_service_desk`,
ou ter ajuste registrado antes da exposicao; nenhum endpoint foi criado em CP1.
Frontend futuro: `/app/accounts/:accountId/service-desk`, sem reciclar nomes `jrc_cockpit`
ou `jrc_service_center`. Nao alterar `jrcService/routes.js`.

Listas futuras: paginacao server-side, filtros validados, ordenacao permitida, mesma ACL nas
contagens e no detalhamento. Erros seguem o padrao nativo; nao refatorar o tratamento global.
O controller base usa resposta 403 vazia para indisponibilidade, sem strings de traducao novas.
`verify_authorized` e `verify_policy_scoped` sao verificacoes de uso do Pundit, NAO substituem
policies concretas corretas; nao desativa-las para contornar um teste falho.

## Eventos, jobs, integracoes e NICO

Documentar futuros eventos com prefixo de dominio inequivoco (ex.: `jrc_service_desk.ticket.created`),
versao, account_id, identificador do recurso, ator/origem, event_id/idempotency_key, instante e
correlation_id. Reutilizar dispatcher/listeners/jobs nativos; decidir compatibilidade com canais
externos antes de publicar. Nao registrar listeners, cron ou workers neste checkpoint.
Emitir efeitos de negocio no momento transacional adequado (tipicamente apos commit).

Jobs nao podem confiar em Current herdado de outra thread/request: reconstruir conta e ator,
revalidar flag/permissoes em cada execucao e limitar retries/concurrency/filas para nao afetar
mensagens/Calling/NICO. A forma persistente de deduplicacao pertence ao checkpoint operacional.
Desabilitar o modulo deve bloquear novos comandos e ter estrategia segura para jobs em curso.
Integracoes opcionais indisponiveis nao devem gerar sucesso ficticio ou mutacoes silenciosas.

## Aceite funcional e KPI (obrigatorio futuramente)

Para cada acao, registrar tela/componente -> endpoint -> policy/scope -> service -> tabela(s) ->
resposta/leitura -> atualizacao da interface -> efeito em dashboard. Validar tambem falta de
permissao, conta incorreta, falha, clique duplicado, concorrencia e refresh.

Para cada indicador: nome, definicao, fonte SQL/consulta, escopos, filtro, janela e fuso,
formula/numerador/denominador, criterio de exclusao, tratamento de lista vazia, origem de cache,
invalidation e drill-down. Teste: valor inicial conhecido em dados de teste -> mutacao controlada
-> valor esperado -> detalhamento coerente -> restricao por outra conta -> refresh.
Nenhum KPI ou dado demonstrativo foi implementado no CP1.

## Ordem e bloqueios

Checkpoint 2 so pode ser autorizado depois da avaliacao do CP1 e das decisoes pertinentes.
Uma aprovacao futura parcial deve explicitar exatamente os subdominios liberados e os bloqueados.
Nao iniciar backend operacional, frontend, fluxos, integracoes ou Projetos como efeito colateral
desta documentacao. Conferir diff, manifestos e testes antes de aprovar qualquer etapa.
