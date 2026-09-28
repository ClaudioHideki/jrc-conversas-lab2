# CP6 atualizado - pendencias e limites

**CANDIDATO PARA HOMOLOGAÇÃO — VALIDAÇÃO NATIVA PENDENTE**

**PENDENTE — validação nativa em Docker/servidor**

| ID | ITEM | DEPENDENCIA | STATUS |
|---|---|---|---|
| CP6-D01 | Inicializacao JRC humana e delegacao estrutural explicita | APROVADA e implementada. Configurar designacao do funcionario e capacidades do cliente explicitamente no destino; executar provas nativas. | PENDENTE DE EXECUÇÃO NATIVA |
| NATIVE | Execucao Rails/RSpec/SQL/Vue/Docker e F5 | Runtime exato e bases isoladas; nenhuma migration executada aqui | PENDENTE DE EXECUÇÃO NATIVA |
| SNAPSHOT-INPUT | Captura operacional de condicoes contratuais/calendario | RecordSlaSnapshotService existe, mas sem API/UI/integacao externa; ensaio automatizado usa somente fixture de teste | PENDENTE FUNCIONAL |
| PORTAL | Identidade externa/portal/SSO | Fora deste candidato; Contact nao autentica cliente | PENDENTE FUNCIONAL |
| FILES | Anexos upload/download autorizado | Associacao Active Storage nao e fluxo entregue; sem endpoints/signed URLs | PENDENTE FUNCIONAL |
| CHANNELS | Resposta publica e primeira resposta real | Sem envio ou marca de primeira resposta por nota interna | PENDENTE FUNCIONAL |
| CALENDAR-EDITOR | Cadastro mestre/editor visual/importacao de calendarios | Existe interpretador de snapshot explicito; nao editor/master | PENDENTE FUNCIONAL |
| NEXT | Assumir proximo/capacidade/competencia | Nao presumir FIFO ou prioridade sem regras operacionais aprovadas | PENDENTE FUNCIONAL |
| CROSS-UNIT | Transferencia entre unidades | Nao autorizada; transferencia atual e dentro da unidade | PENDENTE FUNCIONAL |
| ADVANCED | Relatorios avancados/exportacao/governanca/ativos/aprovacoes/pesquisas/automacoes/NICO operacional | Referencias visuais nao sao API, persistencia ou KPI entregue | PENDENTE FUNCIONAL |
| PROJECTS | Modulo Projetos | Nao implementado, nao iniciado, fora do candidato | N/A |

Uma Account vazia agora possui fluxo manual de inicializacao sob autoridade JRC explicita. Ele nao liga flags, nao cria usuarios ou concede acesso ao funcionario. Estrutura parcial nao e mesclada automaticamente.
