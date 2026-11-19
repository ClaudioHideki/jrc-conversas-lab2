# Relógio de pós-atendimento e leituras antigas

Status: correção preparada, sete cenários nativos preparados; ainda não executados.

## Problema comprovado pela leitura do código

Qualification.operational_payload chama refresh_overdue!. O método anterior usava update_columns após conferir completed_at somente no objeto Ruby. Um objeto carregado enquanto o registro ainda estava pendente podia gravar overdue/exceeded_seconds/updated_at depois de outro fluxo concluir a qualificação ou aumentar seu limite. Isso alterava métricas históricas ou restaurava um excesso calculado com limite antigo.

## Correção

A atualização dos três campos observacionais passa a exigir, na própria instrução SQL, que o registro continue pendente, na mesma conta/membership e com os mesmos started_at, limite e duração usada na fórmula. Em seguida recarrega a linha e confirma que o escopo original de conta/membership foi preservado antes de devolver dados. A leitura de um registro que deixou esse escopo falha com RecordNotFound.

A fórmula nativa de elapsed_seconds é preservada. Não se reinicia started_at, não se conclui atendimento, não se muda motivo/resultado/notas e não se altera o snapshot de regras. A precedência aprovada continua fila → equipe → geral, com bloqueio de conflitos. Esta correção não representa a seleção intermediária de motivo: ela prepara a integridade necessária para essa próxima pendência.

## Verificação preparada

Os sete cenários usam ActiveRecord/PostgreSQL reais na CI: leitura pendente atual; objeto antigo após conclusão; objeto antigo após aumento de limite; leitura antes do prazo; mudança do proprietário/membership; leitura histórica concluída; leituras repetidas preservando identificadores/notas e sem eventos de disponibilidade.

São testes do modelo com dados sintéticos. Não representam uma ligação PABX ou a homologação do formulário completo. As APIs nativas e as regressões existentes continuam no workflow. Nenhuma migration ou dependência nova é necessária. A CI anterior `44448633679` confirmou 1.100 exemplos Rails, com uma falha na asserção sobre associação ActiveRecord ainda carregada; recarga do schema passou com 16 exemplos. Os dois relatórios têm zero pendências e erros fora dos exemplos. Cinco infrações Ruby novas também foram identificadas. A recarga explícita da associação no teste e as correções de complexidade/alinhamento estão preparadas neste incremento. Esses resultados não validam a alteração do relógio; exigir nova execução no novo SHA.
