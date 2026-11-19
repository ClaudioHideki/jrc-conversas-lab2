# Relógio de pós-atendimento e leituras antigas

Status: correção preparada, sete cenários nativos preparados; ainda não executados.

## Problema comprovado pela leitura do código

Qualification.operational_payload chama refresh_overdue!. O método anterior usava update_columns após conferir completed_at somente no objeto Ruby. Um objeto carregado enquanto o registro ainda estava pendente podia gravar overdue/exceeded_seconds/updated_at depois de outro fluxo concluir a qualificação ou aumentar seu limite. Isso alterava métricas históricas ou restaurava um excesso calculado com limite antigo.

## Correção

A leitura pendente bloqueia e recarrega a própria linha com with_lock, confirma que o escopo original de conta/membership permanece igual e recalcula o tempo somente sobre os dados atuais. Uma conclusão ou aumento de limite gravados antes da obtenção do lock são respeitados. A atualização observacional usa update!, preservando as validações e callbacks nativos; não há update_all, exclusão de lint ou desativação de validações. A leitura de um registro que deixou o escopo original falha com RecordNotFound antes de devolver seus dados.

A fórmula nativa de elapsed_seconds é preservada. Não se reinicia started_at, não se conclui atendimento, não se muda motivo/resultado/notas e não se altera o snapshot de regras. A precedência aprovada continua fila → equipe → geral, com bloqueio de conflitos. Esta correção não representa a seleção intermediária de motivo: ela prepara a integridade necessária para essa próxima pendência.

## Verificação preparada

Os sete cenários usam ActiveRecord/PostgreSQL reais na CI: leitura pendente atual; objeto antigo após conclusão; objeto antigo após aumento de limite; leitura antes do prazo; mudança do proprietário/membership; leitura histórica concluída; leituras repetidas preservando identificadores/notas e sem eventos de disponibilidade.

São testes do modelo com dados sintéticos. Não representam uma ligação PABX ou a homologação do formulário completo. As APIs nativas e as regressões existentes continuam no workflow. Nenhuma migration ou dependência nova é necessária. A CI anterior `44448633679` confirmou 1.100 exemplos Rails, com uma falha na asserção sobre associação ActiveRecord ainda carregada; recarga do schema passou com 16 exemplos. Os dois relatórios têm zero pendências e erros fora dos exemplos. Cinco infrações Ruby novas também foram identificadas. A recarga explícita da associação no teste e as correções de complexidade/alinhamento estão preparadas neste incremento. Esses resultados não validam a alteração do relógio; exigir nova execução no novo SHA.

## Primeiro gate do relógio

A CI 44451366097 do SHA d9f977e5 executou 1.109 exemplos principais, com sete erros restritos à criação do usuário dos sete cenários novos: a factory deriva email de display_name, que continha espaços. Os outros 1.102 exemplos passaram, incluindo a revisão de equipes e os dois casos de IDs canônicos. A recarga do schema passou com 16 exemplos. As sete falhas não exercitaram ainda a lógica do relógio e não foram registradas como aprovadas. A fixture passa a usar email único explicitamente sintético em example.test. O controle de tempo usa bloco freeze_time, que restaura o relógio mesmo em exceção.

O lint encontrou duas infrações novas: atualização sem validações e travel_back redundante. A solução inicial condicional é substituída pelo lock/reload/update! descrito acima; o bloco de tempo dispensa a limpeza redundante. Todas as validações e expectativas permanecem. Exigir nova CI no checkpoint corrigido e não reutilizar o gate incompleto como homologação.
