# CP2 - decisoes aprovadas e continuidade

Registro: 25/09/2026. Autoridade: autorizacao humana explicita nesta continuacao.
CP2-D01: **APROVADA - OPCAO A**. CP2-D02: **APROVADA - OPCAO A**.
As alternativas anteriores permanecem integralmente no historico de CP2_DECISOES_PENDENTES.md.
SD-D01 a SD-D05 continuam aprovadas sem reinterpretacao. Somente CP2 autorizado; CP3 nao iniciado.

## CP2-D01 - Account -> Empresa Operadora -> Unidade

Uma Account possui varias operadoras; cada operadora pertence a uma Account. Uma operadora
possui varias unidades; cada unidade pertence obrigatoriamente a uma operadora da mesma Account.
Cada ticket tem exatamente UMA unidade obrigatoria. Sua operadora e derivada da unidade:
nao existe operator_company_id redundante no ticket, nem chamado somente da operadora.
Sem unidade ficticia, default automatico, unidade nula ou compartilhamento implicito entre unidades.
Nao reutilizar Company, Contact, JrcCrm::Organization, Team ou configuracao do NICO como operadora/unidade.
Account continua presente em todos os registros operacionais e determina a fronteira externa.

## CP2-D02 - AccountUser <-> Unidade: somente escopo

A associacao explicita e ativa entre AccountUser e Unidade limita o escopo operacional.
Nao armazena roles, permissoes ou um catalogo de RBAC paralelo. AccountUser continua nativo.
Team/TeamMember e filas organizam a operacao; nao concedem acesso a unidade.
Acesso exige simultaneamente contexto autenticado nativo valido, flag ligada, mesma Account,
vinculo ativo e autorizacao Pundit para a acao. Ausencia de qualquer requisito: NEGAR.
Administrador tambem precisa do vinculo; sem bypass de leitura cross-unit ou cross-account.
Gestao centralizada futura nao e presumida, e nao existe comando de autoconcessao de escopo.

## Aplicacao de SD-D01 a SD-D05

| Decisao | Compromisso do CP2 |
|---|---|
| SD-D01 | Hierarquia separada dos clientes; IDs nativos preservados; Account em todo dominio. |
| SD-D02 | Snapshots versionados das condicoes necessarias e origem externa; sem ERP ou cliente HTTP. |
| SD-D03 | Contact e solicitante, nao autenticacao; sem portal, sessao externa, SSO ou impersonacao. |
| SD-D04 | Snapshot proprio de calendario/SLA e marcos; sem calcular prazos com fallback nem alterar SLA de Conversas. |
| SD-D05 | Menor privilegio e matriz especifica; Pundit e papeis nativos; API futura tera os mesmos limites. |

## Continuacao exata

Baseline unica: JRC-CONVERSAS-SERVICE-DESK-CP1-CONSOLIDADO-20260925.zip.
SHA-256: 657a589816a52e4e0c8d18c20733540269ff638581a072e31b0e74534925ffe4.
Os cinco documentos preparatorios foram recuperados da entrega anterior e conferidos com
seus hashes. Nao foi reconstruido CP1 nem aplicado qualquer patch ao codigo da baseline.
A arvore temporaria antiga nao estava disponivel neste ambiente; a continuidade de conteudo
foi verificada antes desta atualizacao documental. O trabalho/inventario anteriores nao foram refeitos.

## Limites

Aprovacao arquitetural nao e aprovacao de testes. Permanecem pendentes testes nativos nao executados.
Sem frontend, menus, dashboard, portal, calendario visual, relatorios, integracao externa ou Projetos.
Nenhuma decisao CP2-D03+ esta pendente no inicio da implementacao. Registrar nova decisao real
antes da parte dependente; detalhes tecnicos ja cobertos nao sao novas decisoes de produto.
