# Pausa após encerramento da chamada e conclusão do ACW

Decisão aprovada pelo usuário em19/11/2026. Implementação incremental em validação.

Uma solicitação de pausa durante a chamada deve preservar a ligação e aguardar também a conclusão do ACW. Expiração do relógio não equivale a conclusão. Nenhum rascunho ou evento histórico pode ser descartado/reescrito para iniciar a pausa.

O gerenciador nativo já rejeita a troca de estado durante chamada ativa, mas a verificação de ACW pendente protegia apenas available. A candidata passa a proteger paused também, preservando a transação, a versão esperada, as permissões atuais e a semântica de recibos. Offline e registros históricos permanecem sob as regras nativas anteriores. Cinco cenários com modelos reais e API autenticada foram preparados para testar chamada conectada, ACW pendente/vencido, persistência das respostas/disponibilidade e pausa explícita permitida após conclusão.

Isto fecha o início prematuro por API; não implementa ainda uma fila persistente de solicitações de pausa. Até esse próximo incremento, uma operação rejeitada não pode aparecer como pausa agendada ou aplicada. A interface de solicitação/cancelamento, a persistência da intenção e sua aplicação posterior continuam pendentes. O comando nativo do PABX não deve ser usado como atalho: o contrato atual só anuncia ações técnicas disponíveis, sem operação de pausa/ACK homologada.

As mudanças são internas ao JRC e não executam chamadas ao PABX. Confirmação do fornecedor continuará dependente do contrato externo. Revalidar elegibilidade, motivo autorizado e escopo ao criar/aplicar uma intenção futura; preservar a definição capturada e o histórico.

## Incremento persistente preparado após a proteção inicial

A proteção inicial passou nas cinco regressões nativas em304612a4. O incremento seguinte, ainda sujeito à própria CI, acrescenta uma intenção privada por Account/AccountUser, identificada por UUID e corpo imutável. Somente o próprio operador autorizado pode solicitar ou retirar a intenção. Não existe concessão de poderes por campos enviados pelo cliente.

Solicitar exige chamada ativa ou ACW realmente pendente, revisão explícita, versão do estado nativo e revisão própria da intenção. Essa revisão separada muda na criação e nas transições da intenção; relógios e rascunhos não a alteram, e os hashes históricos do estado/ACW permanecem iguais. Depois de uma retirada, uma solicitação atrasada com outro UUID é recusada; uma repetição exata do UUID original recupera o recibo cancelado, sem reagendar a pausa. Uma nova intenção exige nova revisão pelo operador.

O Account mutex e o lock do vínculo serializam criação, retirada, revogação e conclusão do ACW. A aplicação ocorre pelo AgentStateManager nativo, dentro da transação que registra o estado derivado, somente sem chamada ativa nem qualquer ACW pendente. Tempo vencido e gravação de rascunho não concluem ACW. Elegibilidade, ator, conta ativa, fila, cobertura corporativa, motivo e versão do catálogo são conferidos novamente. Mudança incompatível bloqueia a intenção até retirada/revisão explícita; não promove automaticamente uma configuração diferente. A retirada nunca encerra uma pausa já aplicada.

O PostgreSQL protege autoria/conta, unicidade da intenção ativa, corpo imutável e transições terminais. Um recibo aplicado exige o evento nativo correspondente. O ledger permite os ciclos nativos de encerramento de conta/vínculo; não autoriza apagar individualmente a história. A migration20261119193000 é adicional e só poderá ser executada nos bancos sintéticos isolados da CI nesta entrega.

A interface reutiliza o painel e Dialog nativos. Não envia ao abrir: exige confirmação; preserva UUID e corpo quando a resposta é incerta e só repete a mesma operação após nova ação explícita. Contexto de conta/vínculo/revisão impede reaproveitar respostas atrasadas. Um GET condicional observa a transição real, sem enviar comandos automaticamente. Negação de autoridade limpa dados privados. Não há endpoint PABX, ACK ou sincronização de fornecedor simulados como reais.

Justificativas e rótulos privados ficam fora de logs, payloads compartilhados do supervisor e auditoria de configuração. A auditoria nativa da intenção conserva somente metadados de transição; não entra na lista genérica de auditoria da conta, cuja autorização não representa o escopo operacional do outro agente. Consulta administrativa/histórico operacional detalhado continua pendente e não ganha acesso por este incremento.

Validação preparada: testes nativos de entrada, serviço, API autenticada, escopo, integridade/schema e concorrência real PostgreSQL; apresentação Vue separada; dois percursos Chrome reais em quatro projetos (1440/390, claro/escuro), incluindo resposta perdida após commit, repetição idempotente, retirada e persistência. Testes de apresentação não substituem banco/API/Chrome. Os28 testes locais do gate de migrations e o lint estático passaram; os novos cenários Rails/Vue/Chrome ainda não foram executados no SHA deste incremento. Nenhum aceite integral da figura7, das23figuras ou das etapas é declarado por este ADR.

O supervisor autorizado recebe apenas o estado operacional pending/blocked de intenção vinculada a uma fila atualmente supervisionada e com vínculo físico ativo. UUID, motivo, rótulo e justificativa não entram nesse sinal. Sem fila explícita ou fora da cobertura não há sinal compartilhado; o operador conserva o recibo próprio. Esse sinal não concede cancelamento/aprovação ao supervisor e não substitui o histórico operacional detalhado pendente. Testes de API/unidade e apresentação foram acrescentados para o escopo e a ausência de dados privados.
