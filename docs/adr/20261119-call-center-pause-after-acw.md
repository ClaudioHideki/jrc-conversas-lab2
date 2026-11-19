# Pausa após encerramento da chamada e conclusão do ACW

Decisão aprovada pelo usuário em19/11/2026. Implementação incremental em validação.

Uma solicitação de pausa durante a chamada deve preservar a ligação e aguardar também a conclusão do ACW. Expiração do relógio não equivale a conclusão. Nenhum rascunho ou evento histórico pode ser descartado/reescrito para iniciar a pausa.

O gerenciador nativo já rejeita a troca de estado durante chamada ativa, mas a verificação de ACW pendente protegia apenas available. A candidata passa a proteger paused também, preservando a transação, a versão esperada, as permissões atuais e a semântica de recibos. Offline e registros históricos permanecem sob as regras nativas anteriores. Cinco cenários com modelos reais e API autenticada foram preparados para testar chamada conectada, ACW pendente/vencido, persistência das respostas/disponibilidade e pausa explícita permitida após conclusão.

Isto fecha o início prematuro por API; não implementa ainda uma fila persistente de solicitações de pausa. Até esse próximo incremento, uma operação rejeitada não pode aparecer como pausa agendada ou aplicada. A interface de solicitação/cancelamento, a persistência da intenção e sua aplicação posterior continuam pendentes. O comando nativo do PABX não deve ser usado como atalho: o contrato atual só anuncia ações técnicas disponíveis, sem operação de pausa/ACK homologada.

As mudanças são internas ao JRC e não executam chamadas ao PABX. Confirmação do fornecedor continuará dependente do contrato externo. Revalidar elegibilidade, motivo autorizado e escopo ao criar/aplicar uma intenção futura; preservar a definição capturada e o histórico.
