# Conexões WhatsApp — incremento LAB2 de 02/11/2026

Árvore local `codex/lab2-integral-20261102`, sem commit, push, publicação, QR real ou mensagens reais. Base de fixtures PR4 preservada. Este delta não substitui a matriz global nem declara o documento integral concluído.

## Delta por requisito

| IDs da matriz | Implementação e prova local | Limite restante |
| --- | --- | --- |
| WA-L0036, WA-L0037, WA-L0080, WA-L0082, WA-L0167 | Navegação Minhas conexões / Distribuição / Histórico; contexto da conexão preservado; histórico para operador autorizado | Verificação visual em navegador e homologação de sessão real não executadas |
| WA-L0109, WA-L0115, WA-L0201, WA-L0251 | Renomear explicitamente a conexão, com transação e evento antes/depois, sem recriar vínculo ou política | Nenhuma nova permissão de gestão foi concedida ao operador |
| WA-L0110, WA-L0112, WA-L0113, WA-L0126 | Contrato aceita número completo somente com identidade atual confirmada/revisão correspondente. `lastSyncAt` é a última mensagem recebida espelhada com sucesso após aprovação. `checkedAt` permanece separado | `connectedAt` é nulo: não há fonte demonstrada. Número completo fica indisponível sem observação segura; nunca derivado do sufixo. Corrida de pausa validada em PG7/7; sessão WhatsApp real não homologada |
| WA-L0210, WA-L0213, WA-L0216, WA-L0219, WA-L0225, WA-L0247 | Opções de disponibilidade, espera, capacidade e calendário existente do Inbox; horário e fuso reais, sem calendário paralelo; UI e dispatch usam a mesma política | Alterações do calendário pelo módulo original não são novas entradas deste histórico |
| WA-L0223, WA-L0224, WA-L0226, WA-L0227, WA-L0229, WA-L0230, WA-L0231, WA-L0232, WA-L0233 | Validação por conta/Team ativo, gravação atômica, aviso desconectado, política independente da sessão, sem mover atribuições em curso | Inbox representa canal; Team representa fila. Não são intercambiáveis |
| WA-L0187, WA-L0234, WA-L0235, WA-L0245 | Fallback explícito espera/fila padrão/não atribuído; evento deduplicado; elegibilidade existente preservada, disponibilidade e teto por conexão configuráveis | Capacidade já imposta pelo Inbox continua aplicada; opção de conexão não elimina limites de outros módulos |
| WA-L0021, WA-L0249, WA-L0262, WA-L0264, WA-L0266, WA-L0268, WA-L0272, WA-L0274, WA-L0326 | Eventos persistentes de tentativa, transição observada, QR expirado, falha, configuração; histórico de distribuição antes/depois; paginação por cursor em ambos | Transições são observadas pelo polling/control local; não existe backfill completo do provedor. Falhas controladas de desconexão foram cobertas no incremento posterior |
| WA-L0270 | Divergência produz evento bloqueado e deduplicado por revisão | Números esperado/retornado completos não são persistidos no evento: fonte protegida não demonstrada; não inventar dados |
| WA-L0277, WA-L0311, WA-L0315, WA-L0334, WA-L0335 | Metadados permitidos explicitamente; operador recebe resultado/motivo, admin recebe auditoria segura; revalidação do vínculo; append-only em modelo e PostgreSQL | Nenhum segredo/QR/código fica no histórico. Mudança de papel remonta histórico para descartar dados anteriormente autorizados |
| WA-L0254, WA-L0255, WA-L0256, WA-L0257, WA-L0258 | Sem afirmação de implementação neste incremento | Métricas desejáveis ainda precisam consulta e contrato próprios |

## Evidência

- Rails: 71 exemplos, 0 falhas, cobrindo sete arquivos de distribuição, dispatch, política, auditoria e requests Broker. Esse total é a suíte final anterior à refatoração exclusiva de estilo em três arquivos novos; regressão posterior será registrada separadamente.
- Vue: 72 testes, 0 falhas nos quatro arquivos afetados: ConnectionsPage (25), ConnectionPanel (18), ConnectionDistributionPolicy (27), ConnectionHistory (2). Não somar com execuções anteriores sobrepostas.
- RED observado: opções/endpoint/modelo ausentes; lifecycle ausente; paginação/rename ausentes; fallback emitia duas entradas na repetição (corrigido).
- RuboCop: três Ruby novos, nenhuma infração após refatoração. Migration 120000 aplicada apenas no DB sintético; `db/schema.rb` reconciliado seletivamente.
- Broker: unidade health 2/2. PG RED reproduzido pela frente Flow: 6/7, pausa durante I/O retornava READY antigo. Correção usa mapping revalidado e recusa rebind; GREEN 7/7 no PostgreSQL isolado.

## Continuação

Central de Migração em módulo separado conforme plano `docs/superpowers/plans/2026-11-02-migration-center.md`; importadores existentes preservados. Produção, cargas reais e cutover permanecem fora desta execução.

## Revalidação posterior

- Broker health: **7/7** no PostgreSQL isolado, log `output/lab2-control-health-green.log` no checkout Broker.
- Conexões: **35/35** no gate Rails 272, incluindo falha de disconnect, mudança de grants e erro observado sanitizado/deduplicado. Não somar com os 71 casos anteriores sobrepostos.
- Schema preserva função e dois triggers append-only no caminho de schema load. Nenhum comando de backup, dump ou restore foi executado.
- UI focal mais recente: **8/8** = Central 4 + parser 2 + histórico Conexões 2, log `output/specs-20261102/central-ui-history-green.log` no workspace pai. O novo caso verifica o cursor de operações anteriores do lote.
- O gate Rails 272 também expôs um RED de optimistic locking na Central, 11 RED novos NICO e 22 falhas de recuperação de campanha. São acompanhados pelas respectivas frentes; não equivalem a falhas nesses 35 casos de Conexões.
