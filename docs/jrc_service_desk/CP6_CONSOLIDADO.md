# CP6 atualizado - resolucao exclusiva da CP6-D01

**CANDIDATO PARA HOMOLOGAÇÃO — VALIDAÇÃO NATIVA PENDENTE**

**PENDENTE — validação nativa em Docker/servidor**

## 1. Continuidade e decisao

Registro:28/09/2026. Base unica: `JRC-CONVERSAS-SERVICE-DESK-CANDIDATO-HOMOLOGACAO-20260928.zip`.
SHA-256 esperado e conferido ANTES das alteracoes:
`75bf3a187e5fd98430df3148664f136177a6bf58ee18140a4511f0a1cc94e3fe`.
O candidato anterior permanece preservado. Nenhum checkpoint foi reconstruido ou patch reaplicado.
Novo candidato: `JRC-CONVERSAS-SERVICE-DESK-CANDIDATO-HOMOLOGACAO-20260928-R2.zip`.
Hash e tamanho efetivos do ZIP constam no manifesto/checksums externos, evitando referencia circular.

CP6-D01 APROVADA pela mensagem humana nesta conversa. A aprovacao foi registrada antes do codigo
em CP6_D01_APROVADA.md; alternativas anteriores preservadas como historico nao vigente.
SD-D01..SD-D05, CP2-D01/D02 e CP4-D01 mantidas. Nenhuma nova decisao CP6-D02 pendente.

Funcionario JRC autorizado -> formulario manual -> operadora -> unidade -> primeiro UnitMembership
para o cliente selecionado -> auditoria transacional -> recibo relido em GET.
Nao cria AccountUser, UnitMembership ou capacidade para o funcionario. Nao existe seed/job/boot
que concede primeiro acesso, unidade ficticia, autenticacao alternativa ou RBAC paralelo.

## 2. Inicializacao humana

Reutiliza sessao Devise SuperAdmin JA existente mais designacao nominativa protegida:
`JRC_SERVICE_DESK_INITIALIZER_USER_IDS`. Lista ausente/invalida nega. Nenhum ID e preenchido.
O responsavel da instalacao verifica identidade humana e autoridade antes de configurar IDs exatos.
Administrador da Account, email/dominio JRC ou apenas tipo SuperAdmin nao bastam. O pacote nao
cria/promove funcionarios a SuperAdmin. Poderes nativos preexistentes desse usuario fora desta
ferramenta nao foram ampliados nem removidos. Account ativa e flag SD ligada por acao humana previa.

Destinatario: usuario cliente confirmado, com AccountUser existente da mesma Account. Ator, outros
SuperAdmins e usuarios designados inicializadores sao recusados. POST exige CSRF, nomes/codigos,
selecao do destinatario, referencia da autorizacao/motivo e confirmacao. GET/F5 nao concedem acesso.
A tela informa explicitamente que operadora/unidade/vinculo iniciais serao ativos.
Nao se alteram roles, capacidades, flags, clientes, SLA ou usuario existente.

Transacao sob lock da Account cria os tres registros, tres auditorias estruturais Audited e um
recibo consolidado. Falha desfaz o conjunto. Mesma chave/conteudo/autor devolve recibo. Estrutura
parcial/preexistente ou outra tentativa apos inicializacao e negada sem mesclar/apagar dados.
GET do recibo consulta tambem registros atuais e indica mudancas posteriores. Concorrencia real
aguarda PostgreSQL. Nenhum procedimento de reparacao privilegiada foi automatizado.

## 3. Administracao posterior do cliente

Quatro capacidades acrescentadas ao catalogo NATIVO CustomRole.permissions:
- jrc_service_desk_structure_view
- jrc_service_desk_operator_companies_manage
- jrc_service_desk_units_manage
- jrc_service_desk_unit_memberships_manage

As33anteriores preservadas na mesma ordem. Defaults agent23/administrator33 intactos; ZERO novos
defaults. Exigir AccountUser administrator, role valida da Account com concessoes explicitas,
flag/contexto validos e estrutura inicializada. Os manages dependem de structure_view.
Essa autoridade e ESTRUTURAL no nivel Account: nao depende nem concede acesso a chamados.
Sem CustomRoles nativo, a delegacao granular fica indisponivel; nenhum RBAC substituto ou
habilitacao automatica. Sem capacidades novas, administrador comum continua negado.

Listar/criar/editar/ativar/desativar operadoras/unidades/memberships, sem DELETE, mudanca de dono,
codigo ou destinatario. Conceder/reativar membership propria e negado; revogacao propria explicita
permitida. Team nao concede unidade. Revogar membership retira operacao, nao as capacidades
estruturais independentes. Para retirar ambas, revogar ambas. A exclusao de CustomRole preserva
fallback nativo e nao e tratada como revogacao segura do modulo.

## 4. APIs, interface e auditoria

JRC: `/super_admin/accounts/:account_id/service-desk-initialization` e recibo por GET.
Cliente: `/app/accounts/:accountId/service-desk-structure`, no dashboard/sidebar nativos, apenas
com contexto backend estrutural positivo. Nao monta provider operacional nem consulta tickets,
mensagens ou KPIs. Nao utiliza essa autoridade como bypass de TicketPolicy.

Contexto e consultas sao escopados por Account. Escritas usam allowlists/revisao/idempotencia,
FKs/relacoes verificadas e revalidacao da autoridade, inclusive em replays.
Lock Account -> ator/AccountUser/CustomRole -> recursos, compativel com a ordem operacional.
Audited::Audit existente, associado aos objetos SD e nao ao log geral de Account. Autor User,
AccountUser quando houver, Account, unidade, alvo, timestamp, motivo, antes/depois e digest.
Sem promessa de imutabilidade contra SQL privilegiado/retencao externa.

Cliente: POST/PATCH -> GET recibo -> GET registro -> comparacao -> nova lista -> F5.
Falha de releitura e confirmacao pendente; recuperacao usa mesma chave/intencao. Nenhum sucesso
apenas Vue/localStorage. Troca de identidade/flag/capacidades limpa dados; resposta antiga e
ignorada. Foco/visibilidade e timer60s revalidam, nao push instantaneo. Revalidacao da mesma
autoridade preserva rascunho. Backend autoriza novamente cada requisicao.

20 combinacoes verbo/caminho novas:17 API cliente +3 rotas JRC; total acumulado84.
Nenhuma rota de DELETE. Matriz permissao37. Matriz botoes283:252 pendentes de execucao nativa,
29 pendencias funcionais anteriores e2 referencias N/A. Nao sao283botoes simultaneos.
Os22fluxos criticos anteriores continuam pendentes de prova nativa. Roteiro atualizado:
15fases,84 casos manuais, com pre-condicao/acao/resultado esperado/obtido/status/evidencia.
Fases6/7 agora cobrem designacao humana, POST auditado e delegacao explicita.

## 5. Comparacao e arquivos

Contra o candidato CP6 anterior:30 adicionados,32 modificados,0 removidos;9.665 anteriores
identicos e9.727arquivos no total. Dos32modificados,13sao codigo/registro/i18n estritamente
necessarios e19documentacao/matrizes CP6. A lista integral e hashes acompanham a entrega.
Codigo novo:7services/contratos,2policies,2controllers,2viewsERB,6frontend executaveis,1YAML,
5testesRuby (4RSpec+1isolado),2specsVitest+casos compartilhados,2documentos.

ZERO migrations novas/aplicadas. As204anteriores e db/schema.rb intactos. Runtimes, lockfiles,
modelos nativos, authenticator, policies e services operacionais, KPIs, lifecycle/calendario,
jobs, Cockpit/jrcService e specs anteriores preservados byte a byte.
Flag: jrc_service_desk false, feature_flags_ext_1 posicao9 mascara256;71anteriores intactas.

## 6. Verificacoes efetivamente executadas

- Ruby isolado: 85 testes, 1607 assercoes, 0 falhas, 0 erros, 0 skips.
  Novos11testes/145assercoes. Enumeracao ampliada aumenta assercoes do teste antigo de capacidades;
  nenhum teste anterior foi editado para alterar seu resultado.
- Node isolado: 353 casos,353passaram,0falhas,0skips;36novos+317anteriores.
- Sintaxe Ruby:176arquivos. Parsing JS:82scripts,373imports locais resolvidos,1CSS.
  Nao executado compiladorVue, ERB/Rails, Vitest, ESLint ou build.
- Comparacao integral, Git, hashes/CRC/testzip: saidas efetivas nas evidencias externas.
  Essas verificacoes nao equivalem a transacaoSQL, autenticacaoHTTP, concorrencia ou F5.

4RSpec novos cobrem inicializacao manual, vazio/partial, autoridade, ausencia de grant do ator,
CSRF, repeticao, falha atomica, IDs estrangeiros/proprios/staff, delegacao, revisao e auditoria.
2Vitest novos cobrem contratos e negativa de UI. Todos escritos, mas NAO executados nativamente.
Fixtures/doubles sao exclusivos de testes, nao dados retornados pela aplicacao.

**PENDENTE — validação nativa em Docker/servidor**

Tentativas encontraram Ruby3.3.8/Node22.16.0/Bundler2.5.22; requisitos continuam
Ruby3.4.4/Node24.13.0/Bundler2.5.16/pnpm10.2.0. Rails/RSpec/pnpm/Docker/psql ausentes;
bundle3.3 check recusou runtime. Nenhuma migration foi executada. Nao inferir aprovacao de
Rails/PostgreSQL/Vue/Vitest/CSRF/roteamento/browser de testes isolados.

## 7. Pendencias e parada

CP6-D01 resolvida no codigo, sujeita a validacao. Designacao do funcionario, usuario cliente,
flag e capacidades reais precisam de configuracao humana no destino. Nenhum servidor ou usuario
real foi configurado. Estrutura parcial antiga nao recebe reparacao automatica.
Snapshot-input, portal, anexos, canais/primeira resposta real, editor mestre de calendario,
assumir-proximo, transferencia cross-unit, relatorios avancados e integracoes permanecem fora
desta resolucao. Nenhuma funcionalidade futura foi simulada para reduzir pendencias.

Projetos e outro checkpoint NAO iniciados. Encerrar nesta entrega e executar posteriormente
somente o roteiro no Docker/servidor isolado e autorizado.
