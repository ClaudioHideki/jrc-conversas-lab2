# Biblioteca interna versionada de formulários de pós-atendimento

Status: implementação em candidata; aprovação depende da CI nativa e das capturas do SHA correspondente.

A figura9 dos dois Word exige “Gerenciar formulários” na fonte, sem confundir término da chamada e conclusão do ACW. Reutilizamos os validadores puros de campos/respostas do catálogo nativo (texto, inteiro, booleano e seleção); nenhuma autorização, cadastro ou API do Service Desk é reaproveitada para conceder acesso ao Call Center.

O popup é acessível pela seção nativa de Motivos de encerramento e pelas configurações ACW existentes. Lista paginada, busca literal, status, criação, edição, prévia local explicitamente não persistida, arquivamento/reativação e histórico usam as APIs autenticadas da conta. Nenhum parâmetro de conta/unidade/usuário do corpo concede autoridade. O módulo exige configure e a mesma cobertura corporativa global/GROUP da política ACW nativa. Usuários limitados à unidade não recebem a biblioteca global. Auditoria exige audit e audit_logs separadamente.

Identidade e versões são append-only, com FKs compostas de conta, sequência, UUID por operação, ator revalidado sob mutex nativo da conta e CAS. Versões preservam identificadores históricos do ator. SQL rejeita alterações e exclusões diretas; retirada da conta segue o ciclo nativo. Índices únicos evitam duplicação de recibos. Nome/descrição/definição não entram na trilha de configuração; o envelope acw_form é filtrado nos logs. A API responde no-store.

A nova migration é aditiva e posterior ao schema-base; as duas migrations anteriores continuam byte a byte e hash fixados. O gate admite somente as três adições exatas. Reexecução verifica metadados, restrições, funções/triggers e índices contra o recibo de instalação, sem confiar apenas nos nomes de tabelas. Native schema reload e testes de concorrência/persistência são obrigatórios e não equivalem a verificações estáticas.

Respostas obrigatórias distinguem false e0 de ausência. A prévia usa os mesmos campos, sem gravar respostas. Falhas conhecidas mantêm o rascunho; resultado de escrita incerto trava a edição e permite apenas repetição explícita do mesmo UUID/corpo/alvo. Divergência exige recarregar, comparar e confirmar a revisão; não há retry ou sobrescrita automáticos. Mudança de conta ou desmontagem invalida respostas tardias.

## Limites preservados

Cadastrar ou arquivar um formulário não altera regras, hashes ACW legados, snapshots ou chamadas em andamento. O vínculo de regra→versão e o preenchimento privado na qualificação operacional são um incremento separado ainda pendente. O popup informa essa limitação. Não alegar F09-A/F09-B completos por existir uma biblioteca. Nenhuma configuração é enviada ao PABX, e nenhum grant real é criado.

A regra de precedência aprovada permanece fila→equipe→geral, com conflitos no mesmo nível bloqueados; não é redefinida aqui. A relação entre pausa durante chamada e ACW segue a decisão de negócio pendente, sem transição presumida.
