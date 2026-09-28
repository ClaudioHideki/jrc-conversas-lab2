# CP4 - indicadores rastreaveis

PENDENTE — validação nativa em ambiente Docker/local

A fonte unica e TicketQuery, baseada em TicketPolicy::Scope, Account e UnitMembership ativo. DashboardService faz UMA consulta SQL agrupada por ID/nome/familia do status. KpiCounts transforma esse resultado, sem cache nem constantes de contagem. Zero somente para consulta bem-sucedida sem registros.

| KPI | Significado | Regra |
|---|---|---|
| Total autorizado | Todos os chamados que passaram por scope e filtros | Soma de todos os grupos de status |
| Abertos/em atendimento | Familia open | Soma dos status com phase=open |
| Aguardando | Familia waiting | Soma dos status com phase=waiting |
| Resolvidos | Familia resolved | Soma dos status com phase=resolved |
| Fechados | Familia closed | Soma dos status com phase=closed |
| Cancelados | Familia cancelled | Soma dos status com phase=cancelled |
| Ativos | Familias ainda ativas tecnicamente | open + waiting |
| Distribuicao por status | Cada estado configurado pelo cliente | Contagem SQL por status, nome real, filtro pelo ID |

Invariantes: total = open + waiting + resolved + closed + cancelled; active = open + waiting; soma(by_status.count) = total. Nao somar Ativos com as cinco familias, pois e um subtotal.
Filtros: q, status, prioridade, categoria, unidade, operadora, responsavel(AccountUser), fila, origem e Minha Fila. Paginacao e ordenacao NAO reduzem total. Minha Fila significa atribuicao ao AccountUser atual em grants ativos; nao e apenas autoria.
A interface valida Account, carimbo UTC, filtros retornados e as igualdades antes de apresentar os indicadores. Mudanca confirmada incrementa revisao local e refaz leituras. Nenhum contador e incrementado/decrementado otimisticamente no Vue.
A barra de distribuicao usa count/total reais; nao possui series de exemplo. Evolucao temporal, CSAT, violacao SLA e capacidade continuam indisponiveis.

## Teste controlado de 27 chamados

O spec cp4_queries_spec.rb cria 8 registros no status inicial, 12 em outro status configurado da familia open e 7 em um status da familia resolved: 27 = 8 + 12 + 7. As familias correspondem a open=20/resolved=7. Alteracao controlada de um registro resulta em 7 + 12 + 8, total=27 e active=19.
Essa alteracao de fixture pelo model verifica a query, NAO constitui um servico de resolucao aprovado nem contorna CP4-D01 na API. Esse spec SQL ainda NAO executou.
A aritmetica equivalente foi exercitada sobre o codigo puro real em Minitest e nos decodificadores Node; isso nao prova contagem SQL ou o refresh do navegador.
Tambem ha specs de filtros combinados, pagina desconsiderada no KPI, grant revogado, outras contas/unidades, zero real e familias closed/cancelled/waiting.

## Refresh e consistencia

A escrita so recebe confirmacao visual apos acknowledgement valido + novo GET de ticket + comparacao dos campos. Notas e vinculos exigem adicionalmente GET pelo result_id. A listagem e os KPIs recarregam, nao usam sucesso visual temporario.
A verificacao real via navegador/F5, fluxo Rails, transacao PostgreSQL e consulta depois de restart ainda e pendente. Nao declarar essa cadeia como OK a partir da aritmetica isolada.
