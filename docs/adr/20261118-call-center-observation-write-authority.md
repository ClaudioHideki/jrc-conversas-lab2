# Autoridade atual ao registrar observações de atendimento

Estado: implementado na cópia isolada; testes nativos pendentes do próximo SHA.

## Causa

O endpoint nativo autoriza a chamada e a capacidade operate antes de chamar
`CallObservationWriter`. O serviço aguardava somente o lock da chamada e
conferia account_id/revisão. Uma revogação durante essa espera não era
reavaliada antes da gravação. O texto da observação e seu histórico são dados
privados do atendimento; a revisão esperada não substitui autorização atual.

## Correção mínima

- Manter a assinatura do serviço, o endpoint, os campos, o limite de mil
  caracteres, a edição vazia intencional e o conflito 409 existentes.
- Usar AuthorityTransaction na conta antes do lock de CallSession. A ordem
  coincide com FactsProjector e com o processamento de eventos suportados
  por EventReconciler; não introduzir chamada ao fornecedor.
- Depois dos locks, recarregar o vínculo e o usuário e revalidar a capacidade
  operate e a visibilidade da chamada pelo AccessScope nativo, incluindo
  conta, cobertura atual e atribuição. Sem bypass por administrator.
- Só então comparar a revisão e gravar, na mesma transação, a projeção atual
  e o histórico nativo. Uma falha da revisão deve reverter também a projeção.
- Preservar o no-op quando o texto e a revisão atuais são os mesmos. Não
  alterar estado da chamada, atribuição, tabulação ou disponibilidade.

## Validação preparada

Seis exemplos diretos do serviço cobrem persistência/idempotência, perfil
restritivo aplicado depois de carregar o membro, elegibilidade retirada,
atribuição retirada, outra conta e rollback pelo validador nativo da revisão.
Os dois testes preexistentes mantêm suas asserções e passam a declarar uma
conta com o módulo habilitado e uma chamada atribuída ao agente elegível.

Três corridas HTTP adicionais verificam revogação de elegibilidade, perfil
e cobertura corporativa durante espera PostgreSQL real pelo lock da conta.
Não são sleeps para tentar reproduzir uma corrida: há barreiras e consulta
de pg_stat_activity confirmando que a requisição está bloqueada em Account.

Nenhuma execução local pesada, migration, nova permissão, concessão real,
operação PABX, publicação Docker ou deploy integra esta mudança.
