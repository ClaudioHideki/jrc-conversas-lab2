# Estado atual - CP4-D01 APROVADA

A alternativa A foi aprovada explicitamente. Ver CP4_D01_APROVADA.md.
A implementacao desta continuacao nao autoriza CP5.

## Historico anterior preservado (nao e o estado atual)

# CP4 - limite de ciclo de vida

CP4-D01 - DECISAO PENDENTE: regras executaveis de pausa, resolucao, encerramento e reabertura.

SD-D01..05 e CP2-D01/D02 permanecem aprovadas; nao sao reabertas.
O handoff original exige motivos de pausa configurados, efeito configuravel no SLA,
solucao/evidencia conforme politica e janela configurada para reabrir. O CP2 possui
familias de status e snapshots, mas nao representa essas propriedades, janelas nem
o contrato executavel de calendario. Nao basta trocar uma FK e apresentar resolucao.

Alternativa A (recomendada, NAO implementada): politica de ciclo de vida versionada
por unidade/servico, com transicoes explicitamente permitidas, requisitos de evidencia,
motivos e efeitos de pausa, janela de reabertura e regra para novo ciclo de SLA.
Sem politica aplicavel, negar. Impacto: persistencia adicional, configuracao autorizada,
calculo temporal e testes concorrentes/feriados/horario de verao.
Alternativa B: tabela de regras uniforme por Account. Menor flexibilidade para unidades
com contratos distintos; ainda requer valores explicitamente aprovados, versionamento
e o mesmo calculador. Nao adotar defaults silenciosos.

Aprovacao solicitada: propriedade/precedencia da politica de ciclo de vida e, antes da
execucao dependente, parametros/semantica do relogio de pausa e novo ciclo na reabertura.
Nao foi escolhido prazo, timezone, fallback 24x7, janela ou evidencia padrao.

Bloqueado somente: transicoes entre familias open/waiting/resolved/closed/cancelled,
pausa/retomada de relogio, resolver/encerrar/cancelar/reabrir e calculador de SLA.
CP4 permite apenas trocar status ATIVO na mesma unidade DENTRO da familia open;
isso cobre rotulos operacionais configurados (nao gera/renomeia status) e nao alega
resolver chamado. TicketPolicy.transition? anterior continua negado.

Transferencia implementada e apenas atribuicao/fila/equipe na MESMA unidade, usando
AssignTicketService. Transferencia entre unidades nao foi autorizada, nao implementada.
Assumir-proximo continua PENDENTE: faltam regras operacionais de capacidade/competencia/
disponibilidade/ordenacao; nenhum FIFO ou prioridade numerica e presumido.

Nenhum CP5 iniciado. Pacote intermediario registra a parte entregue e esta pendencia.
