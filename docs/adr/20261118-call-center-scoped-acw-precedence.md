# ACW por motivo: fila, equipe e regra geral

Decisão de negócio confirmada pelo usuário em 18/11/2026: fila → equipe → geral, bloqueando conflitos no mesmo nível. Não existe prioridade comercial inventada ou escolha por duração menor.

## Implementação incremental

As regras opcionais de voz ficam na política ACW da própria conta. A API existente exige configure, cobertura global/Group e revisão atual para alterá-las. Não há cadastro paralelo de equipes/filas. O popup existente reutiliza listagens nativas paginadas. Novas linhas ficam inativas até seleção explícita. A escrita e a auditoria ficam na mesma transação. Criação e conclusão de qualificações reutilizam a barreira nativa de autorização operacional após o lock da conta; a conclusão também revalida o acesso nativo à chamada/conversa. Três cenários concorrentes reais cobrem retirada de elegibilidade, perfil e cobertura enquanto o HTTP aguarda o lock.

No início de um novo ACW de voz, o evento nativo preserva as regras aplicáveis, a revisão, o limite inicial e a origem da perna atendida, incluindo as equipes nativas do agente. A fila atual de uma chamada transferida não substitui essa origem. Na conclusão, o motor usa esse snapshot: fila, equipe, geral e, se não existir regra para o motivo, limite global capturado. Ambiguidade bloqueia a conclusão sem gravar um resultado parcial.

ACWs legados sem esse snapshot continuam no limite previamente capturado. Configurações posteriores não modificam os eventos antigos. Reenvio de conclusão permanece idempotente. O payload geral e os leitores sem configure/Group não recebem definições de outras filas/equipes. Regras possuem esquema estrito, limite técnico de 100 entradas/128 KiB e referências verificadas na mesma conta. WhatsApp mantém seu fluxo anterior.

## Limites e critérios ainda abertos

Este incremento não implementa todo o cadastro de encerramentos da figura 9. O motivo é escolhido no envio da conclusão nativa: o relógio inicial conserva o limite geral; a seleção persistida usa o limite da regra na conclusão. Edição/persistência intermediária do motivo e prévia do relógio por motivo precisam de incremento específico com o mesmo snapshot, sem reescrever o histórico.

Conflitos históricos não podem ser resolvidos por troca silenciosa da regra vigente. Uma eventual exceção operacional necessita de política, revisão e auditoria próprias. Não há publicação PABX, formulário paralelo, acionamento externo ou automações de encerramento neste incremento. Permanecem pendentes formulários nativos vinculados, automações por destino e contratos externos.

## Evidência

Os testes nativos preparados cobrem a precedência real na conclusão, conflitos, versões históricas, reenvio, conta estrangeira, revisão, auditoria e privacidade. Os testes Vue cobrem a edição e busca paginada com troca de conta. Quatro novos cenários Chrome com banco sintético e CSS real se somam aos 140 anteriores. A execução do novo SHA ainda está pendente; preparação ou teste estático não equivale à homologação.
