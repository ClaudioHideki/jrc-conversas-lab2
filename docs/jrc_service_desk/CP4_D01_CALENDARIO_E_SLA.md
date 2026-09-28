# Calendario interpretado de snapshot e ciclos - CP4-D01

Esta rodada implementa um INTERPRETADOR de snapshot temporal de contrato fechado; nao
implementa cadastro mestre/editor visual de calendarios, importacao de feriados ou busca
externa. Nao copia o SLA/horario de Inbox/Conversas. Nao inventa janela comercial ou 24x7.

## Fonte explicita

Usa SlaSnapshot do ticket, previamente registrado pelo mecanismo existente e autorizado,
com timezone IANA explicita, origem/versao e condicoes imutaveis. Nao certifica a veracidade
do contrato externo. Nenhum snapshot e provisionado ou preenchido pelo frontend desta etapa.

calendar_conditions precisa conter EXATAMENTE as chaves:
- format: "jrc-sd-snapshot-calendar-v1";
- weekly: objeto com "1" ate "7", cada dia com lista explicita de intervalos HH:MM;
- holidays: lista explicita de datas ISO;
- exceptions: objeto data ISO -> intervalos daquele dia (lista vazia fecha o dia).

policy_conditions.clock_budgets_seconds exige first_response e resolution positivos,
inteiros, informados explicitamente. Esses valores sao duracoes uteis para os relogios,
nao contagens derivadas de graficos. Nenhum timezone/feriado/duracao e escolhido por default.
Nao ha exemplo preenchido automaticamente na aplicacao; horarios e numeros dos specs sao
fixtures de teste, nunca dados operacionais.

## Interpretacao

No contrato v1, excecao da data substitui o dia; sem excecao, feriado fecha o dia; sem ambos,
aplica weekly. Essa regra de precedencia e identificada pelo format versionado. Um snapshot
que dependa de outra precedencia nao deve ser rotulado v1: e rejeitado/precisa de adaptacao
explicita. Nao existe conversao silenciosa de payloads antigos.

Intervalos ordenados, nao sobrepostos, com fim maior que inicio; 24:00 apenas limite final.
Jornadas atravessando meia-noite devem vir divididas por dia. TZInfo converte limites pela
zona explicita; horarios inexistentes/ambiguos de transicao DST sao recusados, sem escolher
o offset por conveniencia. UTC serve somente para armazenar/comparar instantes; nao define
calendario operacional. Feriados locais e fins de semana nao sao presumidos.

elapsed soma a intersecao dos intervalos uteis reais. advance consome a duracao restante nos
intervalos futuros. O limite de busca de 3.660 dias evita processamento sem fim: se exceder,
falha com dependencia, nunca fabrica prazo. Esse limite e tecnico, nao um SLA de 10 anos.

Snapshot ausente, formato antigo, fuso invalido, metas incompletas, horizonte esgotado ou
limite local DST ambiguo retornam dependencia. A API nega a transicao inteira e a interface
nao exibe sucesso. GET nao cria relogios nem corrige payloads.

## Persistencia de execucao

SlaCycle identifica ticket, versao da politica, snapshot, numero e inicio. SlaClock contem
kind, state, budget_seconds, elapsed_seconds (decimal), anchor_at, due_at, achieved_at e
calculator_version. Pausas registram quais clocks foram de fato afetados.

Primeiro ciclo e construido na primeira transicao que precisa de relogio, desde opened_at
porque esse inicio foi explicitamente configurado pela politica. Novos ciclos de reabertura
iniciam no timestamp real da reabertura. Se nao existir ciclo historico para continuar/reabrir,
nega: nao cria uma historia inexistente.

Estados: running, paused, completed, stopped. met? retorna nil quando nao completed.
Nenhuma nota interna conta como primeira resposta. A realizacao do relogio first_response
por resposta real continua dependendo da integracao de canal, fora desta rodada. A API nao
deve tratar stopped como sucesso nem nil como zero/false. Nao se implementa KPI de SLA
cumprido sem essa cobertura e validacao.

Um motivo com clocks:[] nao suspende nenhum relogio. Resume recalcula somente o restante
dos clocks pausados. Se o prazo ja foi consumido, conserva o prazo real anterior; nao o
substitui por agora. Relogios em execucao sao consolidados em transicoes, nao por contador
simulado no navegador. Para tempo ao vivo, a UI informa que a leitura e do estado persistido.

Na reabertura continue_cycle, os relogios escolhidos retomam; intervalo parado e count ou
exclude segundo regra e calendario. new_cycle cria outro conjunto pelo snapshot configurado
e preserva ciclo anterior. Os eventos guardam estados antes/depois mesmo quando o estado
corrente de um clock e atualizado. Sem efeito explicito, negar ou manter apenas keep previsto.

SlaMilestone CP2 e sua unicidade snapshot/kind permanecem: representam marcos do snapshot,
nao uma linha reusada com significado de ciclo diferente. API lifecycle e resumo passam a
expor o ciclo atual quando ele existe; snapshots e eventos anteriores permanecem rastreaveis.

## Limites de validacao

Testes isolados usam zona fixa injetada e repositorios em memoria SOMENTE nos testes.
Eles verificam o algoritmo real, nao TZInfo/Rails/PostgreSQL nem o enforcement das constraints.
Specs nativos incluem timezone real, pausa seletiva, feriados/excecoes, limite DST,
continue/new cycle e integridade. Permanecem sem execucao nativa. Nao houve migration aplicada.
