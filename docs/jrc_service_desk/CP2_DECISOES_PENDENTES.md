# CP2 - estado vigente das decisoes

CP2-D01: **APROVADA - OPCAO A**.
CP2-D02: **APROVADA - OPCAO A**.
Autoridade: autorizacao humana explicita da continuidade do CP2.
Registro normativo: `CP2_DECISOES_APROVADAS.md`.
Nao ha nova decisao arquitetural pendente nesta rodada ate este registro.
O texto abaixo e historico, preservado integralmente; NAO representa o estado vigente.

---

## Historico integral da rodada preparatoria (superado pela aprovacao)

# CP2 - decisoes arquiteturais pendentes

Data: 25/09/2026. Estado: PENDENTE DE APROVACAO HUMANA.
Este registro NAO modifica nem revoga SD-D01 a SD-D05. Nao ha nova alternativa para usar
Company/Organization como operadora, substituir Account, trocar calendario ou criar ERP.
As escolhas abaixo detalham a estrutura e a seguranca que CP1 deixou explicitamente abertas.
Nenhuma das recomendacoes foi implementada. Nao ha DDL, migrations ou codigo operacional.

## CP2-D01 - DECISAO PENDENTE: relacao operadora/unidade e propriedade do chamado

### Problema

SD-D01 exige varias empresas operadoras/unidades por Account e separacao dos clientes.
Nao determina se 'empresa operadora' e 'unidade' sao dois niveis distintos, um unico nivel
operacional ou uma hierarquia variavel. Tampouco fixa se todo chamado precisa de unidade
ou se pode ser propriedade direta da operadora. Isso muda chaves estrangeiras, unicidades,
restricoes de conta, escopo de filas, calendarios, transferencias e politica de acesso.

Evidencia: `DECISOES_APROVADAS.md`, SD-D01, invariantes, deixa cardinalidades e memberships
sem fixacao; SD-D04 aprova Account e calendarios especificos, nao a cardinalidade de unidades.
O inventario nao encontrou cadastro operacional pronto que resolva isso. `Team` e equipe;
`Company` e cliente. `JrcNico::ErpSetting#operator_company_id` e configuracao externa singular
por Account, nao um cadastro multiunidade nem um vinculo de autorizacao.

### Alternativas e impactos

| Opcao | Estrutura | Impacto e limite |
|---|---|---|
| A | Account -> varias operadoras -> varias unidades por operadora; unidade pertence a uma operadora; cada chamado pertence a uma unidade. | Duas entidades operacionais distintas. Empresa do chamado e derivada da unidade, ou validada de forma consistente se houver FK redundante. Facilita calendarios por operadora/unidade. Nao permite chamado sem unidade sem regra adicional. Nao criar unidade ficticia automaticamente. |
| B | Account -> varios escopos operacionais planos; cada escopo representa uma operadora OU unidade. | Uma entidade e uma FK no chamado; menor complexidade inicial, mas nao representa relacao matriz/filial ou heranca de calendario/visibilidade. Evolucao futura pode exigir migracao estrutural. |
| C | Account -> arvore operacional de profundidade variavel. | Admite empresa/regiao/unidade e compartilhamentos futuros, mas exige prevencao de ciclos, regras de ancestralidade e autorizacao recursiva; maior complexidade e risco de escopo fora do CP2. |

### Recomendacao tecnica, NAO aplicada

**Opcao A**, se a operacao distingue empresas e suas unidades. Um chamado tem uma unidade
responsavel e nao e compartilhado implicitamente. A operadora decorre dessa unidade;
Account continua presente em todos os dados operacionais. Nao reutilizar cadastro cliente.
Nao acrescentar referencias redundantes sem restricao que garanta coerencia.

A aprovacao de A deve explicitar se aceita a unidade obrigatoria para o chamado. Necessidade
de chamado diretamente da operadora ou fila compartilhada entre unidades nao pode virar
fallback silencioso. Nenhuma dessas estruturas foi criada nesta rodada.

### Parte bloqueada

Tabelas de operadoras/unidades; FK operacional de tickets/filas/snapshots; unicidades por
escopo; seeds de unidade; services de transferencia; indices e testes correspondentes.
Nao criar tickets com unit_id nulo provisoriamente para aparentar progresso.

## CP2-D02 - DECISAO PENDENTE: origem da autorizacao para operadoras/unidades

### Problema

SD-D05 define menor privilegio e mecanismos nativos. AccountUser registra acesso a Account;
TeamMember registra participacao em equipe. A baseline nao define qual dessas relacoes,
ou qual vinculacao explicita adicional, autoriza atuar em uma unidade. Ter papel de admin,
ser responsavel por chamado ou pertencer a uma equipe nao pode ampliar o escopo por inferencia.

Esta escolha e de escopo de dados, nao aprovacao de novo RBAC. Qualquer opcao deve continuar
usando autenticacao nativa, AccountUser, Pundit e as capacidades nativas aprovadas por acao.
As seis permissoes atuais de CustomRole nao incluem Service Desk: nao reutilizar uma chave
de Conversas/CRM para conceder SD, nem acrescentar silenciosamente catalogo de papeis.

### Alternativas e impactos

| Opcao | Origem do escopo | Impacto e limite |
|---|---|---|
| A | Vinculo explicito entre AccountUser e unidade; papeis/capacidades continuam nativos. | Uma associacao de escopo, sem tabela de papeis/permissoes paralela. Revogacao clara e testes por unidade. Precisa administrar esses vinculos numa etapa autorizada; nenhuma heranca entre unidades. |
| B | Equipes nativas sao explicitamente vinculadas a unidades; TeamMember determina escopo. | Reutiliza participacao em equipe e evita concessao individual, mas mudancas de equipes de Conversas podem afetar SD. Precisa definir unidade por equipe, compartilhamento e revogacao. |
| C | Vinculos individuais e de equipe, com regra de combinacao aprovada. | Mais flexibilidade, mas uniao amplia acesso e intersecao restringe acesso de formas diferentes. Exige precedencia e testes de revogacao; maior complexidade. |

### Recomendacao tecnica, NAO aplicada

**Opcao A**, com acesso operacional calculado pela intersecao de: contexto nativo valido,
feature ligada, Account correta, vinculo de unidade ativo e permissao Pundit para a acao.
O vinculo de unidade contem apenas escopo; nao duplica roles, permissoes ou usuarios.
Equipes/filas sao roteamento e podem restringir a acao, nao conceder unidade por si so.
Sem vinculo explicito, negar tambem para administrador; eventual gestao centralizada de
escopos exige uma acao nativa explicitamente autorizada, nao um bypass de leitura de tickets.

Isto e recomendacao sujeita a aprovacao. A base atual continua negando todas as acoes do SD.
Nenhum schema de vinculos, alteracao de CustomRole ou concessao foi executado.

### Parte bloqueada

Memberships de unidade, scopes concretos de tickets/comentarios/anexos, atribuicao e
validacao de responsavel, grants nativos especificos e testes positivos/negativos de acesso.
E possivel descrever os testes; nao e correto implementar permissao presumida para passa-los.

## O que nao e uma nova decisao pendente

Nao pedir nova aprovacao para Account como tenant, namespaces, fonte contratual externa,
snapshot local, identidade dedicada de portal, calendario proprio, negacao por padrao,
Pundit nativo, Active Storage, manutencao da flag ou ausencia de Projetos: isso ja foi aprovado.
Tambem nao tratar nomes de classes ou escolha do formato de indice como decisao de produto.

Parametros de calculo de SLA e integracao externa continuam fora da implementacao desta
rodada. Nao criar agora um calculador para depois pedir aprovacao de calendario/precedencia.
Se um detalhamento posterior realmente bloquear outro contrato, registra-lo antes da
implementacao dependente. A lista atual nao afirma que todas as decisoes futuras acabaram.

## Encerramento da rodada

Ponto de parada: concluida a verificacao da baseline, leitura dos tres contratos e inventario
nativo; antes da primeira migration e do primeiro model operacional.
SD-D01 a SD-D05: APROVADAS. CP2-D01 e CP2-D02: DECISAO PENDENTE.
Nenhum CP3 iniciado. Nenhum ZIP definitivo ou intermediario CP2 gerado.
