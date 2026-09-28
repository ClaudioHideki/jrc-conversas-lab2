# CP4-D01 - contrato executavel de politica de ciclo de vida

CP4-D01: APROVADA, alternativa A, pela mensagem humana que autoriza esta continuacao.
Nao existe nova decisao arquitetural pendente nesta rodada. Nenhuma politica ou vinculo foi
provisionado automaticamente. A autorizacao desta implementacao nao aprova os testes nativos.

## Selecao, identidade e historia

Account -> OperatorCompany -> Unit e UnitMembership permanecem intactos. O novo Service e
uma identidade minima de servico operacional NA UNIDADE (nao contrato, ERP ou Company).
O chamado pode informar service_id na criacao; o servico precisa estar ativo, na mesma
Account/unidade e selecionado pelo contexto autorizado. Ausencia de servico nao inventa
cadastro: ela permite somente a politica explicitamente configurada da unidade.

Precedencia: politica servico+unidade configurada -> politica padrao da unidade.
Sem politica valida: negar. Se uma politica especifica EXISTE mas esta desabilitada, nao
contornar a restricao por fallback para a politica menos especifica. Politica global nao existe.

Novos chamados fixam a versao aplicavel durante a criacao quando ela existe. Um chamado
legado/sem politica continua sem versao; a primeira transicao bem-sucedida fixa a versao
dentro da mesma transacao. Uma consulta GET nunca fixa versao ou cria relogios. Um ticket
ja vinculado nunca migra silenciosamente para a versao atual. Servico e unidade do ticket
nao sao alterados pelo editor generico.

Cada publicacao acrescenta LifecyclePolicyVersion, autor nativo, numero, definicao, mapa
ID/status/familia, metadados de publicacao e digest SHA-256. O ponteiro da politica avanca,
mas versoes anteriores e eventos sao preservados. Desabilitar explicitamente a politica
nega novas operacoes inclusive em versoes antigas; reabilitar nao troca suas versoes.
Status removido/inativo ou com familia diferente daquela publicada nega a transicao.
Versoes/transicoes sao append-only no dominio ActiveRecord, nao uma garantia contra SQL privilegiado.

## Configuracao autorizada e interface

A tela Configuracoes existente recebeu um editor avancado de definicao JSON, nao um
construtor grafico de fluxos. Usa componentes nativos, unidade autorizada e capabilities
do backend. Publicacao exige administrador nativo E UnitMembership ativo na unidade;
agente sem concessao e admin sem vinculo sao negados. Nenhum RBAC paralelo.

Servicos minimos podem ser cadastrados nessa area com codigo/nome/active explicitamente
informados. Nao ha unidade default, ativacao de usuario ou concessao de escopo. A API de
servicos nao implementa o catalogo completo nem altera contratos.

POST de publicacao recebe unit_id e policy:{name,service_id,enabled,expected_version,definition}.
expected_version=0 representa explicitamente uma primeira publicacao; versao obsoleta gera
conflito, nao sobrescrita. Criacao de servico recebe unit_id e service:{name,code,active}.
A tela verifica o POST com GET independente e compara IDs, definicao, digest e metadados.
Falha da releitura nao e apresentada como confirmacao de persistencia.

## Formato fechado da definicao (sem defaults de negocio)

Todas as chaves de nivel superior sao obrigatorias: schema_version=1, transitions,
pause_reasons, reopen e sla. Campos desconhecidos e definicoes incompletas sao rejeitados.
O numero 1 identifica o contrato de software, nao uma politica padrao.

Cada item de transitions exige:
- key: identificador textual da regra;
- action: pause, resume, resolve, close, cancel, reopen ou work_status;
- from_status_ids: IDs reais dos estados de origem autorizados na mesma unidade;
- to_status_id: ID real do estado de destino, ativo;
- requirements: note/solution/evidence/classification booleanos explicitos e fields;
- clocks: efeitos explicitos first_response e resolution (keep, stop, complete conforme acao);
- end_pause: booleano explicito para encerrar uma pausa em uma transicao que nao seja resume.

As familias tecnicas limitam as combinacoes coerentes. A configuracao pode restringir
mais, nunca transformar cancelamento em resolucao:

| Acao | Origem tecnica permitida | Destino |
|---|---|---|
| pause | open | waiting |
| resume | waiting, com pausa registrada | open |
| resolve | open/waiting | resolved |
| close | resolved | closed |
| cancel | open/waiting/resolved | cancelled |
| reopen | resolved/closed/cancelled, conforme regra explicita | open |
| work_status | open | open |

O endpoint anterior work_status tambem precisa de regra publicada. Sem ela, negar; ele nao
continua como caminho alternativo para contornar a politica. TicketPolicy.transition?
nao se tornou permissao generica: LifecycleActionPolicy + selector + regras governam a acao.

## Evidencias e requisitos

requirements:{note:boolean, solution:boolean, evidence:boolean, classification:boolean,
fields:{nome:{label:string,type:text|integer|boolean,required:boolean,equals?:scalar}}}.
Os campos extras sao valores da transicao, preservados no evento, nao alteracoes arbitrarias
nas colunas do ticket. equals permite exigir um valor especifico, inclusive true. Um false
nao satisfaz um requisito configurado equals:true. Nao ha eval ou expressao executavel livre.

note e solution sao texto; evidence_note_ids identifica notas REAIS, autorizadas, do mesmo
chamado/Account/unidade. Nao aceitar ID de outro chamado, blob ou URL como prova automatica.
Exigencia de classification verifica a categoria real do ticket. Limites tecnicos: ate
30 campos, 50 IDs de evidencia unicos, 20.000 bytes para nota/solucao e 4.000 para campo texto.
Sao limites de entrada, nao prazo SLA ou configuracao de negocio.
Anexos externos, aprovacao humana de evidencia e regras nao representadas por esse contrato
nao sao simulados; exigirao evolucao especifica.

## Pausa e retomada

pause_reasons:[{code,name,status_ids:[IDs de destino],clocks:[first_response/resolution]}].
Uma regra pause exige motivo compativel com seu destino. clocks:[] e uma lista explicita:
registra espera/motivo/autor, mas NAO pausa nenhum relogio. waiting sozinho nao implica pausa.

Uma unica pausa aberta por ticket. Registro possui versao, ciclo quando aplicavel, motivo,
relogios, inicio/autor e fim/autor. Resume exige pausa existente e retoma somente os relogios
que ela realmente pausou. Resolver/encerrar/cancelar com pausa aberta exige end_pause:true.
Sem essa regra, negar, em vez de fechar automaticamente o intervalo.

## Reabertura

reopen exige allowed:boolean. Quando allowed:true, exige tambem:
window_seconds (inteiro positivo), anchor_action (resolve|close|cancel),
expired (deny|require_new_ticket), sla_cycle (continue_cycle|new_cycle),
inactive_time (count|exclude), resume_clocks, new_cycle_snapshot (same_snapshot|latest_snapshot).
Todas essas chaves existem no contrato mesmo quando allowed:false; nesse caso seus valores
nao habilitam reabertura e podem ser nulos/listas vazias. Quando desabilitado, regras reopen
sao rejeitadas na publicacao.

A janela usa segundos decorridos desde a ULTIMA transicao real da acao-ancora configurada;
nao se presume janela em horas uteis. O instante limite e inclusivo. Sem evento de origem,
sem regra, ou apos a janela: negar. require_new_ticket informa a necessidade de criar um
novo chamado pelo fluxo normal; NAO cria outro chamado automaticamente nem reutiliza IDs.

continue_cycle retoma SOMENTE os relogios configurados. inactive_time conta ou exclui o
intervalo parado conforme calendario aplicado. new_cycle cria numero novo, preserva ciclo
anterior e escolhe snapshot anterior ou mais recente somente conforme new_cycle_snapshot.
Cada transicao registra escolha, versao, ciclo/snapshot, estado anterior e posterior.
Nenhuma escolha e global ou hardcoded.

## SLA

sla:{mode:not_applicable|calendar_snapshot,initial_start:opened_at} e obrigatorio.
not_applicable so funciona se explicitamente publicado: clocks precisam ser keep e motivos
nao podem pausar relogios. Registra a transicao de negocio como sem SLA aplicavel, nao cria
prazo/clock ficticio. Ticket com ciclo previo nao pode ser reinterpretado assim.

calendar_snapshot exige formato de calendario e metas compativeis; ver CP4_D01_CALENDARIO_E_SLA.md.
Somente resolve pode completar resolution. Uma transicao interna NUNCA declara primeira
resposta realizada; esse marco depende da integracao com a comunicacao real. stop pode
parar relogios sem alegar cumprimento, e keep deixa explicitamente seu estado anterior.

## Atomicidade e confirmacao

Unidade e ticket sao bloqueados pelos mecanismos CP2. Flag/Account/AccountUser/grant sao
revalidados no comando. Requisicao informa versao otimista do ticket, versao da politica e
chave de idempotencia. Repetir mesma chave/mesmo payload retorna a transicao original;
mesma chave/payload diferente falha. Nao usar cache do navegador como prova.

Status, pausa, clocks, binding, transicao e TicketEvent participam da mesma transacao.
Dependencia de calendario, evidencia invalida ou falha de evento desfazem todo o comando.
O cliente faz POST -> GET transicao pelo ID -> compara payload -> GET ticket -> GET lifecycle.
So depois confirma e invalida listas/dashboard para nova consulta. Falha da confirmacao
mantem estado incerto e permite repetir a mesma chave/payload. Troca de Account cancela/limpa.
F5 recupera os dados pelas APIs; essa prova nativa ainda precisa ser executada.
