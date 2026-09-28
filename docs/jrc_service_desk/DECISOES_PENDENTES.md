# Service Desk - estado vigente e historico das decisoes (CP1)

## Estado vigente - CP1-R2, 25/09/2026

As cinco decisoes receberam aprovacao explicita do usuario nesta rodada. O registro normativo
vigente e `DECISOES_APROVADAS.md`, que descreve escolhas, invariantes, efeitos e limites.
Nenhuma das cinco direcoes arquiteturais continua como DECISAO PENDENTE.

| ID | Estado vigente | Decisao aprovada |
|---|---|---|
| SD-D01 | APROVADA | Multiplas empresas operadoras/unidades por Account, separadas das empresas-clientes. |
| SD-D02 | APROVADA | Fonte contratual externa e snapshots locais versionados das condicoes aplicadas. |
| SD-D03 | APROVADA | Identidade dedicada de portal vinculada a Contact; SSO apenas preparado conceitualmente. |
| SD-D04 | APROVADA | Calendario proprio do Service Desk por Account e eventualmente por operadora/unidade. |
| SD-D05 | APROVADA | Matriz especifica prevalente; menor privilegio; negacao por padrao e autorizacao nativa. |

Detalhes operacionais ainda nao definidos deverao ser registrados antes de implementar suas
dependencias, em checkpoint autorizado. Nao reabrir as escolhas ja aprovadas por conveniencia.
Falta validacao nativa para o aceite tecnico do CP1; aprovar arquitetura nao aprova os testes.
Nenhuma decisao concede acesso operacional ou autoriza executar o Checkpoint 2.

## Historico integral - CP1-R1 (NAO E O ESTADO VIGENTE)

O bloco abaixo preserva integralmente as alternativas, divergencias e bloqueios registrados
antes da aprovacao. As expressoes DECISAO PENDENTE dentro dele sao historicas, nao atuais.
Este arquivo conserva seu nome original para nao quebrar referencias da primeira entrega.

```markdown
# Service Desk - registro de decisoes pendentes (CP1)

As alternativas abaixo NAO sao decisoes adotadas. O codigo dependente permanece bloqueado.
Responsavel por decidir: produto/administracao JRC com validacao tecnica e de seguranca.
Nenhuma escolha aqui pode autorizar automaticamente o checkpoint seguinte.

## SD-D01 - Empresa-cliente versus empresa operadora/unidade

**DECISAO PENDENTE.**

Fato verificado: o tenant nativo e `Account`; autenticacao e vinculo passam por `AccountUser`.
`Company` (Enterprise) e `JrcCrm::Organization` representam cadastros de clientes no contexto
comercial; `JrcCrm::CompanyAdapter` escolhe o modelo conforme disponibilidade e flag.
Isso nao prova que representem empresas operadoras/unidades autorizadas do tenant.
A matriz distingue tenant, empresa, unidade, equipe, carteira, fila e registro.

Alternativas a validar:
- uma empresa operadora por Account, com unidades internas;
- varias empresas operadoras sob uma Account, com unidades e vinculos de autorizacao;
- uma estrutura corporativa externa como fonte, vinculada explicitamente a Account.

Confirmar tambem qual cadastro de empresa-cliente e canonicamente usado no destino e como
preservar a identidade quando `companies` e habilitado/desabilitado. Nao trocar o significado
de IDs entre Company e Organization; IDs numericos iguais nao significam a mesma empresa.

Impacto: schema de escopos, foreign keys, membership, consultas, indices, portal, contratos,
relatorios, arquivos e Projetos. Bloqueia migrations que contenham `company_id`/`unit_id`, ACLs
por empresa/unidade e adaptadores que escolham silenciosamente a identidade do cliente.

Parte resolvida: Account e obrigatorio e NAO sera substituido por outro tenant. Equipe nao e
empresa; contato solicitante nao e automaticamente representante de todos os clientes da empresa.

## SD-D02 - Fonte contratual e limites de consumo/faturamento

**DECISAO PENDENTE.**

Fato dos anexos: tela 17 determina que CRM origina/renova, Service Desk consome e Financeiro
fatura. A base contem propostas/produtos e integracoes ERP, mas o schema auditado nao apresenta
um dominio contratual operacional completo correspondente a vigencia/cobertura/franquia/SLA.
Nao assumir que proposta aceita seja um contrato vigente.

Alternativas:
- consultar o ERP/sistema contratual do ambiente por adaptador identificado e autorizado;
- desenvolver posteriormente um dominio contratual minimo compartilhado no mesmo Rails;
- combinar fonte externa canonica com snapshot local versionado das condicoes aplicadas.

Confirmar sistema e identificadores, conta/empresa titular, vigencia, versao, servicos cobertos,
ativos, franquias, excecoes, vencimento/cancelamento e comportamento quando a fonte estiver indisponivel.
Confirmar se um chamado sem contrato pode existir e com qual regra; nao conceder cobertura ficticia.

Impacto: contrato/servico do chamado, SLA, consumo, financeiro e idempotencia. Bloqueia models,
migrations e adaptadores contratuais, selecao automatica de cobertura e eventos de cobranca.
Nenhum cliente HTTP, credencial, tabela de contrato ou fake provider foi introduzido.

## SD-D03 - Identidade e autenticacao do portal

**DECISAO PENDENTE.**

Fato: o portal requerido e autenticado e acessa as mesmas entidades do core. O Help Center
existente e base de conteudo; `Contact` nao comprova por si so uma identidade autenticada.
O acesso interno usa usuarios e AccountUser; nao cadastrar todo cliente como agente para contornar isso.

Alternativas:
- identidade externa dedicada vinculada a Contact/empresa, reutilizando mecanismos de autenticacao do Rails;
- federacao com provedor de identidade do cliente, com vinculo explicito e revogavel;
- autenticacao controlada por convite/link de uso unico, se os requisitos de risco forem aprovados.

Definir comprovacao de identidade, convites, expiracao, revogacao, recuperacao, MFA quando exigido,
representacao de empresa, usuarios com varias empresas e matriz de acesso aos chamados/arquivos.
Definir aprovacao e auditoria de impersonacao; leitura do portal pelo agente nao concede login de cliente.

Impacto: principals, sessoes, tokens, rate limit, download, links assinados e isolamento.
Bloqueia schema de identidades externas e qualquer endpoint/autenticacao/impersonacao do portal.
Nenhuma rota publica nem alteracao de autenticacao existente foi criada.

## SD-D04 - Propriedade do calendario e semantica temporal

**DECISAO PENDENTE.**

Fato: SLA existente usa `Sla::BusinessHoursService`, inbox, working_hours e timezone; nao e um
calendario neutro de chamados. A especificacao de Service Desk exige feriados, excecoes,
pausas, primeira resposta/resolucao, fuso e preservacao das condicoes aplicadas.
A precedencia excecao > servico contratado > contrato > cliente > padrao e descrita como sugerida.

Alternativas:
- calendario compartilhado de Account/empresa, reutilizavel por Service Desk e futuros Projetos;
- calendario proprio do Service Desk com contrato de leitura reutilizavel, sem dependencia de Inbox;
- adaptador para calendario externo canonico com versao/snapshot local.

Decidir propriedade e administracao, fonte de feriados/excecoes, defaults, precedencia contratual,
versao aplicavel, tratamento de virada do dia e horario de verao e quais estados pausam cada relogio.
Nenhum pais/fuso/jornada/feriado, calculo ou fallback 24x7 sera hardcoded por conveniencia.

Parte resolvida: prazos e instantes devem ser calculados no backend; armazenamento de instantes
em UTC e conversao por timezone explicito no contrato; preservar snapshot/versionamento das
condicoes aplicadas, sem recalcular historico retroativamente de forma silenciosa.

Impacto: schema de calendario, snapshots e motor SLA; bloqueia migracoes e calculos dependentes.
Nao alterar `working_hours`, `SlaPolicy` ou calculo de SLA de conversas nesta etapa.

## SD-D05 - Concessoes e divergencias da matriz de permissoes

**DECISAO PENDENTE.**

Modelo resolvido: autenticacao nativa + AccountUser coerente + Account ativa + flag + policy
server-side + scope por dados + permissoes de campo. O papel define teto, nunca acesso global.
A base atual tem papeis agent/administrator. A extensao de CustomRole aceita seis capacidades;
nenhuma chave nova foi inserida e nenhuma permissao de outro modulo sera emprestada.

| Area | Handoff Service Desk (coluna Operar do agente) | Matriz especifica (secao 4) | Ponto a aprovar |
|---|---|---|---|
| Automacoes, tela 18 | Consulta/uso | Nao | Ocultar/negar ao agente padrao ou conceder consulta especifica? |
| Configuracoes, tela 21 | Consulta/uso | Nao | Sem acesso padrao ou consulta limitada? |
| Contratos, tela 17 | Sim | Somente leitura, valores restritos | Separar cobertura operacional, valores e alteracao contratual |
| Pesquisas, tela 19 | Sim | Somente leitura conforme politica | Separar visualizar notas, enviar pesquisa e configurar |
| Portal, tela 22 | Sim | Somente leitura, impersonacao preferencialmente auditada | Definir acao e identidade, sem assumir login irrestrito |
| Ativos, tela 16 | Sim | Limitado, consulta no escopo | Decidir criacao/edicao por papel tecnico |
| Conhecimento, tela 12 | Sim | Consulta/rascunho; publicacao por permissao | Separar criar rascunho, revisar, publicar e conteudo interno |
| Filas/SLA/Catalogo, telas 9-11 | Consulta/uso | Somente leitura/uso | Tornar explicito que uso nao concede configuracao |

Alternativas de autoridade funcional: adotar a matriz especifica como prevalente e corrigir
as tabelas genericas; ou aprovar uma matriz consolidada de excecoes por acao/escopo. Em ambos
os casos, acesso nao concedido explicitamente permanece negado. O CP1 nao escolhe entre essas
alternativas: BasePolicy nega inclusive para admin, e nao ha telas para expor.

Alternativas de persistencia de capacidades: estender CustomRole pelo mecanismo Enterprise
nativo se esse for o requisito do destino; ou aprovar uma extensao compativel com instalacoes
sem esse recurso. Nao criar um motor paralelo nem exigir licenca sem decisao de produto.

Super Admin: o documento descreve administracao entre tenants, mas nao usar esse papel como
bypass operacional nas APIs de Account. Acesso excepcional requer mecanismo nativo explicito,
contexto de conta e auditoria; nao foi implementada impersonacao ou novo privilegio.

Impacto: ACL de filas/registros/campos, roles customizadas, convidados, delegacao e dados sensiveis.
Bloqueia concessoes operacionais, alteracao de catalogo de permissoes e schema de memberships novos.

## Condicao para retirar um bloqueio

Registrar ID da decisao, opcao escolhida, responsavel/data, fonte/justificativa, invariantes,
impacto em schema e seguranca, testes de acesso negativo e arquivos do checkpoint autorizado.
Uma decisao resolvida nao autoriza executar checkpoints posteriores automaticamente.
```
