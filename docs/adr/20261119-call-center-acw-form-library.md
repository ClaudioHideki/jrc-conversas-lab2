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

## Diagnóstico nativo de19/11

A primeira execução93ffea06provou38/39exemplos de recarga, com1falha de reexecução do recibo;48infrações Ruby impediram os próximos gates. O checkpoint315ab97areduziu-as a3e preservou metadados nas fases fresh/reload/RSpec (run44518350072, artefato14527207589, SHA-256ae5f24a1f954451366a020d2c119969fa562014f9b5cf93d9f6f03891c472cd8).

A diferença é exclusivamente a definição textual do CHECKde status: PostgreSQL move a coerção do array varchar[]→text[] para os elementos ao reprocessar o dump. Colunas, índices, funções e triggers coincidem. Os hashes do componente de restrições diferem; o recibo reprova corretamente a divergência textual. Não ignoramos essa restrição nem normalizamos SQL arbitrário: a nova migration usa explicitamente os literais e a coluna como text, mantendo apenas active/archived. A reexecução e a recarga serão novamente obrigatórias, com teste negativo de alteração do conjunto de status.

O auxiliar do recibo permanece autocontido na migration, como classe aninhada; a regra[Style/OneClassPerFile](https://docs.rubocop.org/rubocop/latest/cops_style.html#styleoneclassperfile)permite esse escopo. Nenhuma exclusão de lint foi adicionada.

Os metadados de diagnóstico são classificados separadamente de RSpec. A colisão do sufixo schema-rspec.jsonno leitor externo foi reproduzida por testes; metadados não contam como exemplos nem suprem relatórios obrigatórios ausentes. O resultado315ab97acontinua reprovado. A correção precisa de nova prova nativa, não de reaproveitamento da aprovação7d55fe76.
