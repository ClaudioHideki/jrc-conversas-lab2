# Backoffice, filas, SLA e pendencias - integracao LAB2

Base: a598ec066b890d101b1905967506d30ab692a132 (Metas publicado).
ZIP SHA-256: 22390ad3e23213d29e5021e0da574650ac94d3856976b765de3342f7c7c34f73.

Integracao em tres vias usando o ZIP de Metas como ancestral do candidato,
preservando as correcoes existentes no Git. Nenhum arquivo removido.
O ZIP tambem inclui CRM-PROP-ACCEPT-01, ausente da base publicada.
Backoffice referencia JrcCrm::Contract; nao existe um contrato paralelo.

Correcoes minimas sobre o candidato:
- Sem prazo automatico de dois dias quando nao existe SLA configurado.
- Automacao repetida conserva fila, responsavel e prazos ja atribuidos.
- Filas e politicas configuradas prevalecem sobre o fallback de monitoramento.
- Pendencias bloqueantes impedem avancar qualquer etapa.
- Calendarios invalidos sao rejeitados; consumo considera dias e horas uteis.
- Pausas congelam o consumo/monitoramento; retomada conserva o saldo em horas uteis.
- Monitor usa o fuso da conta, serializa a avaliacao e audita violacoes dos tres prazos.
- Atribuicoes e transferencias possuem auditoria; evidencia de pendencia respeita limite de anexos.
- Atividade criada na devolucao tem sua referencia persistida na pendencia.
- Criacao manual serializada pelo Pedido; GET de elegibilidade nao escreve.
- Backfill idempotente conserva referencias existentes e nao cria vencimentos.

Validacoes reais e SHA final estarao no relatorio de entrega apos o Actions.
Gates anteriores mantidos; adicionados testes Backoffice/JrcOperations, aceite,
scheduler, reversibilidade estrutural e backfill com dados existentes.
O down do backfill conserva dados operacionais; nao e uma inversao dos dados.
O down estrutural remove tabelas/colunas novas e sera testado apenas no banco CI.

Nenhum deploy, Compose, banco de producao ou container atual alterado.
Antes de deploy futuro, planejar backup e executar as duas migrations no ambiente
adequado. Trocar a imagem nao reverte o schema nem os dados do banco.
