# CP6 atualizado - achados acumulados

**CANDIDATO PARA HOMOLOGAÇÃO — VALIDAÇÃO NATIVA PENDENTE**

**PENDENTE — validação nativa em Docker/servidor**

| ID | ACHADO | FONTE | TRATAMENTO | STATUS |
|---|---|---|---|---|
| CP6-A01 | CRUDs unitarios incompletos | ConfigurationController / ConfigurationService / ConfigurationManager | Implementadas consultas, criacao, edicao, ativacao/desativacao, revisao e recibo independente para cinco recursos. Sem exclusao. | PENDENTE DE EXECUÇÃO NATIVA |
| CP6-A02 | Autoridade para estrutura inicial nao definida | UnitPolicy / OperatorCompanyPolicy / UnitMembershipPolicy | CP6-D01 APROVADA. Ver CP6_D01_APROVADA/IMPLEMENTACAO; manual JRC + capacidades estruturais nativas, sem bypass operacional. | PENDENTE DE EXECUÇÃO NATIVA |
| CP6-A03 | Booleano de disponibilidade da criacao | UiContextService | Uma expressao que podia produzir false era testada por nil. A permissao agora exige um registro inicial verdadeiro e a policy. | PENDENTE DE EXECUÇÃO NATIVA |
| CP6-A04 | Campos de classificacao perdidos na projecao | Presenter / helpers/contracts.js | phase, initial e position foram incluidos explicitamente; sem exposicao de campos nao permitidos. | PENDENTE DE EXECUÇÃO NATIVA |
| CP6-A05 | Reuso da rota de catalogo com chave antiga | CatalogView.vue | Chave de estado e observacao do recurso agora reagem a troca de catalogo; nao reutilizam resultados do recurso anterior. | PENDENTE DE EXECUÇÃO NATIVA |
| CP6-A06 | Fase de status publicada antes de existir ticket | TicketStatus#phase_cannot_relabel_existing_tickets | Impede mudar fase referenciada em qualquer versao publicada, mesmo sem chamado. Nome/atividade seguem editaveis; o historico nao muda de familia. | PENDENTE DE EXECUÇÃO NATIVA |
| CP6-A07 | Desabilitacao explicita de politica com referencias inativas | PublishLifecyclePolicyService | Ao desabilitar a mesma definicao, preserva o mapa historico anterior. Nao revalida como nova politica ativa nem reinterpreta a versao anterior. | PENDENTE DE EXECUÇÃO NATIVA |
| CP6-A08 | Historico podia expor conteudo de notas fora da capacidade | HistoryProjection / LifecycleReadService / Presenter | Campos de nota/solucao/evidencias/custom fields e informacoes de SLA tem projecoes separadas. Conteudo original continua armazenado. | PENDENTE DE EXECUÇÃO NATIVA |
| CP6-A09 | Transicao exigindo evidencia que o ator nao pode ler | LifecycleActionPolicy / LifecycleTransitionService / LifecyclePanel | Nega input protegido sem notes_view e filtra regras com requisitos protegidos; nenhuma ampliacao silenciosa de capacidades. | PENDENTE DE EXECUÇÃO NATIVA |
| CP6-A10 | Auditoria de catalogos poderia escapar pelo log geral da Account | ConfigurationAudit / AuditLogsController nativo inspecionado | Reuso da tabela audits com associated=Unit; nao anexar payload privado a Account.associated_audits. Account e ator no metadata. Recibo scoped; controller nativo intacto. | PENDENTE DE EXECUÇÃO NATIVA |
| CP6-A11 | Mensagens remanescentes diziam que CP3/CP4 nao gravavam | i18n en/pt/pt_BR jrcServiceDesk.json | Textos de formulario, notas, estados e ciclo refletem o candidato; nao afirmam homologacao ou execucao nativa. | PENDENTE DE EXECUÇÃO NATIVA |
| CP6-A12 | Confirmacao e incerteza de escrita administrativa | ConfigurationManager / LifecyclePolicyEditor | Novos CRUDs exigem recibo+GET; antigas publicacoes/servicos verificam ID retornado. Timeout nao e traduzido em certeza de falha. Mesmo intento/chave na recuperacao de catalogo. | PENDENTE DE EXECUÇÃO NATIVA |
| CP6-A13 | Codigo de placeholder relacionado inalcancavel | TicketDetailView.vue | Removidos somente um controle desabilitado num ramo impossivel e rascunho nao utilizado; formulario real de vinculo foi preservado. | PENDENTE DE EXECUÇÃO NATIVA |
| CP6-A14 | Build Node usava tag movel apesar de .nvmrc exato | docker/Dockerfile | Node pinado em 24.13.0-alpine; pnpm install exige frozen-lockfile. Versoes declaradas e lockfiles intactos. Pull/build ainda pendentes. | PENDENTE DE EXECUÇÃO NATIVA |
| CP6-A15 | Dois services sem referencia operacional no app | FindTicketService / RecordSlaSnapshotService | Retidos com classificacao explicita: consulta de dominio testada usada como contrato e gravacao interna sem consumidor HTTP/UI. Nao cria novos endpoints para esconder lacuna. | PENDENTE FUNCIONAL |
| CP6-A16 | Fontes dos indicadores | DashboardService / TicketQuery / KpiCounts / LiveKpis | Consulta agrupada autorizada e equacoes preservadas; nenhuma correcao aritmetica necessaria por inspecao. Prova SQL/UI ainda pendente. | PENDENTE DE EXECUÇÃO NATIVA |
| CP6-A17 | Flags, contexto e respostas obsoletas | BaseController / BaseService / OperationalContext / guards / session helpers | Flags e limites foram preservados. APIs reautorizam; limpeza frontend possui revalidacao por foco/visibilidade/60 s, nao push instantaneo. | PENDENTE DE EXECUÇÃO NATIVA |
| CP6-A18 | Escopo nativo indisponivel | Logs em VALIDACOES | Suites Rails/RSpec/SQL/Vue nao iniciaram; nenhum resultado nativo foi promovido a aprovado. | PENDENTE DE EXECUÇÃO NATIVA |
| CP6-D01-A19 | Autoridade inicial nao definida | InitializerAuthority / InitializeAccountService | Agora designacao nominativa + sessao SuperAdmin; POST manual e transacao com auditoria; nenhum grant do ator | PENDENTE DE EXECUÇÃO NATIVA |
| CP6-D01-A20 | Administracao do cliente sem capacidades estruturais | Capabilities / StructurePolicy | Quatro capacidades novas explicitas, sem default admin/agent, escopo somente estrutural | PENDENTE DE EXECUÇÃO NATIVA |
| CP6-D01-A21 | Acoes estruturais sem consumidor real | StructureView / StructureController | Pagina estrutural nativa, seletores reais, GET recibo e registro, sem DELETE | PENDENTE DE EXECUÇÃO NATIVA |
| CP6-D01-A22 | Mensagens antigas sobre CP6-D01 pendente | docs/jrc_service_desk | Decisao aprovada e roteiro/matrizes atualizados; alternativas anteriores sob historico nao vigente | PENDENTE DE EXECUÇÃO NATIVA |
