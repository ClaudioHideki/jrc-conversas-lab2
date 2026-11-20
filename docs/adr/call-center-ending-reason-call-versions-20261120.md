# Catálogo de encerramentos por chamada e filas — 20/11/2026

Status: implementação interna em preparação; testes nativos e Chrome deste incremento ainda pendentes.

A figura 9 e a confirmação do usuário exigem motivo cadastrado nas filas explicitamente selecionadas, preservando a regra de chamadas já iniciadas. O catálogo continua sendo a configuração nativa da conta, com a permissão global de configuração existente. Não há cadastro paralelo nem ativação em contas reais.

Cada alteração efetiva do catálogo grava uma versão imutável na mesma transação do Account e da auditoria obrigatória. A versão preserva a definição exata, o ID da auditoria e os primitivos de autor/data efetivamente registrados; ausência histórica de usuário não cria um vínculo fictício. O PostgreSQL calcula o SHA-256 e valida a procedência, a sequência e a imutabilidade. A retenção posterior da auditoria não elimina a definição selada.

Novas chamadas recebem a versão conhecida na data de início, a partir das datas comprovadas da auditoria. Chamadas já existentes na atualização permanecem sem vínculo novo; não são retroativamente recatalogadas. Alterações de catálogo, desativação de motivos ou retirada de uma fila só afetam novas chamadas. A escolha da fila operacional vem da perna nativa atendida; o contexto original de ACW é gerado no banco e imutável. A precedência fila/equipe/geral, os seis campos v1 e os snapshots de formulários anteriores permanecem intactos.

Nas filas selecionadas, um motivo ativo dessa versão é obrigatório mesmo com o modo global de voz opcional. O rascunho pode ficar sem motivo, mas uma classificação inválida não é gravada; a conclusão exige o motivo cadastrado e o resultado nativo. Nenhum temporizador encerra automaticamente o ACW. As APIs e o SQL rejeitam a violação. Fora dessas filas, conserva-se a compatibilidade com escolhas legadas.

O mesmo endpoint privado de contexto da própria qualificação retorna somente revisão, hash, obrigatoriedade e código/nome dos motivos ativos congelados. Continua exigindo usuário ativo, operação autorizada, titularidade, acesso atual à origem e cobertura da unidade/fila original. Os IDs nunca concedem acesso. A interface reutiliza o popup do catálogo, o seletor nativo paginado de filas e o editor de encerramento do Hoya; não pede o catálogo administrativo ao operador.

A nova migration não altera as cinco anteriores. Um upgrade com catálogo existente exige sua cadeia exata de auditorias; ausência ou divergência bloqueia a atualização. Os testes de upgrade copiam somente estruturas e dados sintéticos nativos em um schema temporário transacional do banco descartável e restauram o search_path. Instalação, upgrade populado, reexecução, recarga do schema, imutabilidade e concorrência são critérios obrigatórios.

O bloqueio nativo de exclusão de conta com evidências de atendimento é preservado. A aposentadoria de uma conta sem essas referências não deve deixar versões órfãs. Não se removem registros para contornar FKs.

Uma reversão para imagem anterior a este recurso, após ativar filas obrigatórias e deixar a voz global opcional, requer tratar/drenar chamadas em andamento e revisar a política; uma imagem antiga não conhece a nova exigência. Não há deploy ou rollback autorizado nesta tarefa.

Os cenários Chrome usam apenas contas sintéticas guardadas no runner: uma chamada anterior à ativação continua opcional; uma posterior mantém a versão 2 enquanto a configuração administrativa evolui para 4, com revisão, rascunho, recarga e conclusão no componente Hoya real. Isso não homologa SIP, ACKs, comandos, publicação ou disponibilidade externa do PABX.

A recarga de schema não é prova de restauração de dados de backup. A restauração histórica completa não foi executada nesta tarefa e exige o procedimento nativo previamente revisado para históricos imutáveis; nenhum backup ou mecanismo de restauração existente foi alterado.

A rotina nativa EventReconciler corrige started_at quando chega um call.created mais antigo. Essa correção operacional é preservada: ending_reason_captured_started_at registra a data inicialmente usada para selecionar a versão, enquanto o started_at operacional continua corrigível. A versão e sua data de captura permanecem imutáveis, inclusive após conclusão ou eventos repetidos. O teste usa o contrato normalizado existente com dados sintéticos; não comprova assinatura ou ACK real do PABX.
