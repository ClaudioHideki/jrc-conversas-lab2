# 2026-11-18 — Origem operacional e visibilidade nativa

Status: implementado para validação, sem aceite nativo antecipado.

## Evidência e decisão

O formulário CallWorkspace já usa as APIs de casos/retornos, mas não envia unidade/fila. A cobertura corporativa nativa oculta registros sem mapeamento operacional. Não corrigir isso ampliando o AccessScope: resolver a chamada informada pelo escopo de chamadas existente e derivar seus campos operacionais omitidos na criação. Unidade explícita e Case pai são conferidos pelos respectivos escopos. Atualizações com nova origem reautorizam essa origem; campos não enviados não provocam reatribuição de histórico.

Depois de persistir, a mesma lista nativa deve encontrar o registro antes do commit. Uma origem/fila/unidade inacessível ou registro invisível provoca rollback, incluindo evento obrigatório do Case, no mutex Account introduzido no incremento anterior. Não copiar dados de outra chamada ou inferir vínculo por telefone. As FKs compostas continuam protegendo Account; autorizações de unidade e chamada não são substituídas por FKs.

Não amplia a política nem a visibilidade: uma perna de chamada não concede membership de fila. A fila herdada precisa passar pela mesma regra nativa; explicitamente negar continua preferível a gravar um retorno que o operador não pode consultar. Cliente antigo sem cobertura restritiva mantém seu comportamento nativo. Não altera migrations, SQLs, modelos ou permissões.

## Prova exigida

Dezessete cenários nativos: origens corretas, visibilidade, histórico, unidade derivada, mesma conta/unidade proibida, chamada sem atribuição, outra conta, troca de origem, fila não associada, Case pai oculto e rollback de registro invisível. Executar somente em corporate_gratuity_disposable sem transação de fixture; exclusão restrita aos Accounts recém-criados pelo próprio spec. Quatro cenários de Chrome nos dois tamanhos/temas usam a interface real, API/banco sintético e filas explicitamente associadas, preservando a recusa da outra cobertura.

## QA e limites

A CI 44309567421 provou 884 principais e 34 concorrentes, mas dois testes esperavam que a exceção escapasse. test.rb mantém show_exceptions=true; conservar a política e exigir HTTP 500, spy do save! atingido e provas de rollback sem transação externa. Não relaxar o estado esperado nem declarar testes bloqueados aprovados.

Vínculos diretos a contato/empresa, identidade estável de nova tentativa de callback, fluxo de página completa e as demais figuras continuam abertos. Decisão de pausa aprovada separadamente preserva legado e exige ativação explícita do catálogo por conta; não foi ativada/implementada aqui. Contrato PABX permanece externo.
