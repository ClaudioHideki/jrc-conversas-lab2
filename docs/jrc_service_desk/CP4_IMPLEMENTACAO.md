# CP4 - implementacao e limites

CP4 IMPLEMENTADO PARA REVISÃO — VALIDAÇÃO NATIVA ACUMULADA PENDENTE

PENDENTE — validação nativa em ambiente Docker/local

## Arquitetura implementada

OperationsController herda a base CP1 e centraliza guardas nativas, cache no-store, erros e transacao consistente das leituras. Controllers especificos expoem contexto, lookups, ticket e dashboard, sem endpoints de escrita generica em cadastros.
Presenter projeta campos explicitos. Policies do CP2 continuam autoritativas; novas LookupPolicy e WorkStatusPolicy nao constituem outro RBAC. Custom roles continuam sem novas concessoes.
TicketQuery e compartilhada por lista e DashboardService. CatalogQuery faz escopo e autorizacao dos cadastros. RelatedRecordsQuery separa notas, eventos, prazos e vinculos; autorizacao nativa da conversa e reavaliada.
CreateTicketWorkflowService reutiliza criacao e vinculo CP2 na mesma transacao, registrando creation_context_recorded. TicketEvent::TYPES recebe apenas esse evento adicional. A unica reclassificacao nova e open -> open, sem transicao entre familias, calculo ou alteracao do SLA de Conversas.

## Frontend

CP3 visual foi continuado. Um cliente de comandos separado preserva o antigo cliente GET-only e seus contratos. OperationalSession controla envio, concorrencia local, rejeicao, acknowledgement e readback. Novo sucesso visual depende de GET valido e comparacao dos campos; notas/vinculos exigem tambem readback individual.
TicketForm salva e abre o ID retornado apenas depois da confirmacao. TicketOperations atribui/transfere dentro da unidade e altera estado de trabalho. TicketActivity lista e grava notas internas, lista eventos reais e vincula conversas sem copiar mensagens. LiveKpis mostra contagens reais ou estado indisponivel.
Revogacao/troca de contexto cancela e limpa dados. Respostas atrasadas nao repovoam outra sessao. Um aviso generico de readback pendente pode permanecer depois de perder visibilidade, sem restaurar dados do ticket.
Chaves de criacao/notas ficam na memoria da tentativa; nenhum localStorage ou banco falso. Apos refresh antes de confirmar uma tentativa, conferir a listagem antes de novo envio, pois a nova pagina nao possui a antiga chave. API ainda impede duplicacao quando a mesma chave e reutilizada. Idempotencia nao significa deduplicar toda intencao humana com uma chave diferente.

## Banco, escopo e preservacao

Nenhuma migration CP4, nenhuma alteracao de schema.rb, seeds, flags, jobs ou dependencias. As 203 migrations anteriores permanecem. Nao se afirma que foram aplicadas aqui.
Somente config/routes.rb recebe registros adicionais fora do namespace/pastas Service Desk. Backend CP2 preservado, salvo o tipo de evento aditivo. Nenhuma edicao para mascarar testes pendentes.
Cadastros operacionais/grants nao sao criados automaticamente. Administrador continua precisando de UnitMembership ativo. Transferencia entre unidades nao foi autorizada.

## Pendencias funcionais

CP4-D01: politica executavel de ciclo de vida/pausa/evidencias/reabertura e calculador temporal. Bloqueia apenas a parte dependente. Sem cronometro/efeito de pausa ficticio.
Assumir proximo depende de regra de capacidade/competencia/ordenacao; permanece desabilitado. Upload/download autenticado, respostas por canais, dominios complementares, configuracao/provisionamento, portal e integracoes continuam pendentes, sem simulacao.
Projetos e CP5 nao foram iniciados. Este pacote intermediario mantem as pendencias explicitas; nao representa todos os fluxos de Service Desk concluidos.

## Riscos tecnicos a validar

Fixtures nao validam HTTP/SQL real. Somente as suites nativas e smoke podem confirmar autoload, routes, Pundit, constraints, locks, build e montagem das telas.
GETs com REPEATABLE READ usam um snapshot por request; revogacao e reconsultada em requests seguintes. Escritas mantem locks CP2. Ensaiar corridas reais.
Catalogos nativos e vinculos avaliam autorizacao por registro antes de contar; isso pode custar uma varredura e consultas adicionais. Medir paginas grandes, tempo de query, uso de memoria e potencial N+1 antes de ampliar limites (maximo100 por pagina).
Atribuicao pode remover a visibilidade do ator conforme policy; a API pode ter persistido embora o readback retorne403/404. Nesse caso a tela nao inventa rollback nem acesso; mostra aviso/negacao.
O historico continua append-only no dominio, nao contra operador SQL privilegiado. Riscos de FKs CP2 para merge/exclusao continuam documentados, sem alteracoes incidentais.
