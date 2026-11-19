# Relógio de pós-atendimento e leituras antigas

Status: correção de relógio validada nos sete cenários nativos em 490cd3a8; gate global ainda bloqueado por preparação de dois testes Vue e alinhamento Ruby. Nova execução exigida após essas correções.

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

## Execução nativa do relógio — SHA 490cd3a8

A CI 44453345207 executou e aprovou os sete cenários de qualification_clock_refresh_spec.rb sobre PostgreSQL real descartável. Foram aprovados 1.270 exemplos Rails distintos (1.109 principais, 76 de concorrência, 85 corporativos), mais 16 de recarga do schema; todos com zero falhas, pendências e erros externos. Artefato 14496678489, SHA-256 9e62486f1026e1811ecdab327684a144b3517e72b57396e0ed82dd4113fa61f6.

A execução global permaneceu reprovada: uma infração de alinhamento no e-mail sintético e dois testes Vue de navegação PABX que não instalavam o Vuex exigido pelo componente. Os outros 571 exemplos Vue passaram. Corrige-se a preparação desses dois testes com uma store sintética explícita e preservam-se as mesmas verificações de visibilidade e rota. Não se adiciona fallback no componente nem se remove checagem de autoridade. Build e Chrome ficaram bloqueados e não são declarados aprovados.
