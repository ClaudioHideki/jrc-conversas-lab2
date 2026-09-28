# Service Desk - decisoes arquiteturais APROVADAS (CP1-R2)

## Registro e autoridade

- Registro: CP1-R2, 25/09/2026.
- Decisor: usuario responsavel pelo JRC, por aprovacao explicita na continuacao do Checkpoint 1.
- Fonte primaria: mensagem que aprova nominalmente SD-D01, SD-D02, SD-D03, SD-D04 e SD-D05.
- Status das cinco decisoes: **APROVADA**.
- Este registro substitui o estado pendente da rodada CP1-R1, nao a base oficial do codigo.
- As alternativas e motivos originais continuam integralmente em `DECISOES_PENDENTES.md`,
  identificados como historico nao vigente.
- Aprovacao arquitetural NAO equivale a aprovacao tecnica dos testes e NAO autoriza CP2.

Unica base oficial: `jrc-conversas-nico-v12-2-7-comercial-integrado-main (2)(1).zip`.
SHA-256: `0e8d7e18e244ffef0e045d5c14428f2bc6702dacb9c4d508236a7fa292a1f7c4`.
Service Desk (`jrc_service_desk`) e Projetos (`jrc_projects`) sao modulos adicionais e
independentes. Nenhum substitui Conversas, Cockpit/jrcService, CRM, Campanhas, NICO, Calling,
E-mail, Contatos, Empresas, Help Center ou outro modulo existente. Projetos nao e implementado.

## SD-D01 - Multiplas empresas operadoras/unidades por Account

**Status: APROVADA.**

**Decisao:** uma Account pode conter multiplas empresas operadoras/unidades. A estrutura
operacional e conceitualmente separada das empresas-clientes. `Contact` e `Company` mantem
seu significado nativo relacionado ao cliente. `JrcCrm::Organization` preserva sua funcao
atual no CRM. Nao reutilizar silenciosamente esses cadastros como operadora ou unidade.

**Invariantes para as etapas autorizadas futuramente:**
- `Account` continua sendo a fronteira externa de isolamento; nenhuma empresa/unidade amplia
  esse limite. A autorizacao interna adiciona restricoes, nao outro mecanismo de tenant.
- Varios escopos operacionais podem existir na mesma conta. Um vinculo a uma unidade nao
  significa acesso implicito as outras. As permissoes devem usar mecanismos nativos.
- Reutilizar usuarios, agentes, equipes, contatos e empresas-clientes sem alterar sua semantica.
- Referencias de cliente preservam tipo/origem e ID; IDs iguais de modelos diferentes nao
  identificam automaticamente a mesma empresa. O adaptador CRM nativo permanece inalterado.
- Nao fixar nomes de tabelas/colunas, cardinalidades internas ou memberships nesta rodada.

**Impacto futuro:** dados, escopos, consultas, relatorios, arquivos e contratos precisarao
respeitar Account mais o escopo operacional autorizado. A modelagem sera do CP2, se autorizado.
**Aceite futuro necessario:** duas unidades da mesma conta e duas contas distintas; testar
negacao cruzada em leitura, mutacao, exportacao, arquivos, contagens e jobs.
**Mudanca no CP1-R2:** registro conceitual; zero models operacionais, tabelas ou vinculos novos.

## SD-D02 - Fonte contratual externa + snapshots locais versionados

**Status: APROVADA.**

**Decisao:** a fonte contratual canonica e externa. O Service Desk preservara localmente,
com versionamento, as condicoes necessarias de SLA, cobertura, franquias e demais condicoes
aplicadas. Nao criar um ERP ou assumir que uma proposta do CRM e um contrato vigente.

**Invariantes para as etapas autorizadas futuramente:**
- O snapshot de condicoes e uma evidencia aplicada, nao um segundo cadastro mestre contratual.
- Cada calculo deve ser rastreavel ate a origem/versao externa e a versao local efetivamente
  usada, dentro da Account e do escopo operacional corretos.
- Atualizacao externa deve produzir nova versao aplicavel; nao reescrever silenciosamente as
  condicoes historicas que um chamado utilizou. Recalculo intencional exigira regra/auditoria.
- Copiar apenas condicoes necessarias e autorizadas; nao importar todo o ERP nem credenciais.
- Indisponibilidade externa nao autoriza cobertura ficticia, sucesso simulado ou faturamento.

**Detalhamento futuro, nao inventado aqui:** fornecedor/API, identificadores, payload,
sincronizacao, freshness, falhas, vigencia e regra para chamado sem contrato. Antes de uma
implementacao depender de uma regra ainda indefinida, registrar DECISAO PENDENTE especifica.
Isso nao reabre a escolha arquitetural ja aprovada.
**Aceite futuro necessario:** alterar condicoes externas e comprovar que o chamado anterior
continua referenciando o snapshot usado e que a mudanca nao duplica consumo/cobranca.
**Mudanca no CP1-R2:** documentacao; nenhuma tabela, integracao, credencial ou provedor ficticio.

## SD-D03 - Identidade dedicada de portal vinculada a Contact

**Status: APROVADA.**

**Decisao:** o portal tera identidade propria vinculada ao `Contact` nativo do JRC. Preparar
o desenho para federacao/SSO futuro, sem implementar SSO agora. Sessao interna de agente nao
e autenticacao de cliente; a existencia de um Contact tambem nao prova identidade autenticada.

**Invariantes para as etapas autorizadas futuramente:**
- Preservar Contact como cadastro do cliente, separado do mecanismo de autenticacao do portal.
- A identidade externa tera vinculo explicito e validado com a conta/contato e permissoes
  de acesso aos registros. Nao transformar clientes automaticamente em agentes/AccountUser.
- A eventual federacao tera vinculacao explicita; nao confiar em e-mail/telefone/ID recebido
  como prova de identidade. Nao criar adaptador SSO especulativo no CP1.
- Reaproveitar os mecanismos compativeis de autorizacao do JRC sem RBAC paralelo.
- Impersonacao de cliente nao decorre de ser agente, administrador ou Super Admin.

**Detalhamento futuro:** convite, verificacao, sessao externa, expiracao, revogacao,
recuperacao, MFA se exigido, representacao de empresa, rate limits e impersonacao auditada.
**Aceite futuro necessario:** sessao de agente nao autentica cliente; Contact sem identidade
verificada nao concede acesso; arquivos/links/API respeitam revogacao e escopo.
**Mudanca no CP1-R2:** contrato documentado; zero endpoints publicos, sessoes, SSO ou identidades.

## SD-D04 - Calendario proprio do Service Desk

**Status: APROVADA.**

**Decisao:** calendario proprio do Service Desk, no escopo de Account, podendo haver
calendarios especificos por empresa operadora/unidade. O calendario devera suportar horario
comercial, timezone, dias uteis, feriados, excecoes, precedencia e snapshots/versionamento
das condicoes usadas pelo SLA.

**Invariantes para as etapas autorizadas futuramente:**
- Nao alterar `SlaPolicy`, calendario ou calculo do SLA atual de Conversas.
- Um calendario do Service Desk nao e o horario de uma Inbox copiado ou reapontado implicitamente.
- A Account delimita propriedade e acesso; calendarios de operadora/unidade mantem esse limite.
- Explicar qual versao de calendario/politica produziu o prazo de primeira resposta/resolucao.
- Preservar historico aplicado; mudancas de feriados ou jornada nao reescrevem silenciosamente
  compromissos antigos. Calculos sao do backend, nao do relogio do navegador.
- Nao hardcodar timezone, pais, jornada, feriados ou fallback 24x7.

**Detalhamento futuro:** prioridade exata entre calendarios/regras concorrentes, defaults,
origem de feriados, estados de pausa, horario de verao e virada do dia. A hierarquia de escopo
aprovada nao fixa sozinha todos esses criterios. Nao implementar calculador antes de defini-los.
**Aceite futuro necessario:** calendarios diferentes em duas unidades, virada do dia,
feriados/excecoes, snapshot historico e nao regressao do SLA de Conversas.
**Mudanca no CP1-R2:** documentacao; zero calendario operacional ou alteracao no SLA existente.

## SD-D05 - Matriz especifica, menor privilegio e autorizacao nativa

**Status: APROVADA.**

**Decisao:** a matriz especifica do Service Desk prevalece sobre as descricoes genericas do
handoff. Aplicar menor privilegio e NEGAR por padrao quando houver duvida. Nao criar RBAC
paralelo. Estender os mecanismos nativos de autorizacao/permissao somente quando necessario
e de forma compativel. Frontend nao substitui a mesma restricao no backend/API.

| Area | Resolucao arquitetural da divergencia |
|---|---|
| Automacoes | A negativa da matriz para agente padrao prevalece sobre consulta/uso generico. |
| Configuracoes | A negativa da matriz para agente padrao prevalece; sem concessao por conveniencia. |
| Contratos | Leitura operacional e valores financeiros sao permissoes distintas; operar generico nao autoriza escrita nem valores. |
| Pesquisas | Leitura conforme politica nao autoriza enviar/configurar; acoes nao concedidas permanecem negadas. |
| Portal | Consulta nao concede identidade de cliente, sessao externa ou impersonacao. |
| Ativos | Consulta limitada ao escopo nao concede criar/editar globalmente. |
| Conhecimento | Consulta/rascunho nao concede publicacao; proteger conteudo interno e exigir permissao de publicar. |
| Informacoes financeiras | Nao inferir acesso a valores a partir de acesso a chamado, contrato, dashboard ou exportacao. |
| Filas/SLA/Catalogo | Consulta/uso nao concede administracao de regras. |

**Invariantes para as etapas autorizadas futuramente:**
- Preservar autenticacao, AccountUser, contexto Current e politicas Pundit nativos.
- Disponibilidade da feature e associacao a Account sao pre-requisitos, nunca permissao final.
- Aplicar os mesmos limites em registros, campos, relacionamentos, buscas, KPIs, exportacoes,
  downloads, jobs, eventos e ferramentas NICO. Ocultar um botao nao autoriza sua API.
- Avaliar compatibilidade da extensao nativa com a instalacao antes de acrescentar capacidades;
  nao emprestar uma permissao CRM nem criar catalogo de papeis paralelo.
- Em CP1, `BasePolicy` continua negando TODAS as acoes-base, inclusive para administrador.
  Esta aprovacao de principios nao cria automaticamente concessoes operacionais.

**Aceite futuro necessario:** acesso direto a API, outro usuario/unidade/Account, campos
financeiros, publicacao, exports e ferramentas; todos devem negar acesso nao concedido.
**Mudanca no CP1-R2:** registro da prevalencia e dos limites; zero RBAC, capability ou concessao nova.

## O que esta resolvido e o que continua fora desta etapa

As cinco direcoes arquiteturais estao resolvidas e aprovadas. Nao ha pendencia de escolha
entre as alternativas SD-D01 a SD-D05. Parametros de implementacao e operacao mencionados
acima serao definidos antes do trabalho dependente no checkpoint expressamente autorizado.
Nao os tratar como schema, regra executavel ou funcionalidade ja entregue.

O CP1 permanece sujeito a validacao nativa com Ruby 3.4.4, Node 24.13.0, Bundler 2.5.16,
pnpm 10.2.0 e dependencias bloqueadas pela base. Testes estaticos/isolados nao substituem
Rails/ActiveRecord/Zeitwerk/RSpec/Featurable/Vitest nem autorizam avancar automaticamente.

**CHECKPOINT 2 NAO INICIADO.** Nenhuma aprovacao neste documento permite inicia-lo.
