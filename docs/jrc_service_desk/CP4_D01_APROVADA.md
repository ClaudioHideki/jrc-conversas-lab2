# CP4-D01 - APROVADA / alternativa A

Registro: 28/09/2026. Autoridade: autorizacao humana explicita nesta continuacao.
Baseline unica: CP4-INTERMEDIARIO-20260925.zip
SHA-256: 2444d57589577423db47d0f21c40856a20a0491549b2a884ac92f918a5c26975

Politica versionada por Unidade/Servico. Precedencia: servico+unidade configurado,
seguido da unidade somente quando nao existe vinculacao especifica. Uma vinculacao
especifica desativada/invalida nao pode ser contornada pelo fallback. Sem versao
aplicavel, negar. Account, UnitMembership e Pundit continuam obrigatorios, inclusive admin.
A versao e fixada no ticket na criacao quando aplicavel; tickets anteriores sem vinculo
fixam a versao na primeira transicao autorizada. Eventos anteriores nao sao reinterpretados.
Publicar nova versao altera a referencia para novos vinculos, nunca tickets ja vinculados.
Desativacao explicita da politica bloqueia novas transicoes, inclusive nas versoes fixadas.

Pausa depende de motivo e lista explicita de relogios, nunca somente da familia waiting.
Resolucao valida requisitos configurados no backend. Reabertura exige janela e regra
explicita de ciclo existente/novo; expiracao nega ou exige novo chamado sem cria-lo.
Nao existe encerramento automatico nem prazo fixo de reabertura. Sem configuracao, negar.
SLA usa snapshot explicito com timezone IANA e contrato de calendario versionado; dados
incompletos/legados incompativeis sao DEPENDENCIA, nao fallback de horario/24x7.

Ficam preservadas SD-D01..05, CP2-D01/D02, todas as pendencias de CP1..CP4 e a flag desligada.
Nao iniciar CP5. O registro de aprovacao precede as migrations e codigo dependente.

PENDENTE — validacao nativa em ambiente Docker/local.
