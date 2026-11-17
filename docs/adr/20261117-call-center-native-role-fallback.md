# Call Center: retirada de perfil sem aumento implícito de autoridade

Status: decisão técnica aceita para implementação incremental em 17/11/2026.

## Problema observado

Na base `a3355707`, PATCH sem `custom_role_id` preserva o perfil. Entretanto,
enviar explicitamente null, promover um agente sem perfil ou excluir um perfil
atribuído pode ativar o fallback nativo de administrador/agente. Isso concede
capacidades sem passar pela comparação de alçada existente.

## Contrato e decisão

- Calcular as capacidades efetivas anteriores e posteriores com a própria
  ModulePolicy; não duplicar uma lista de privilégios legados no controller.
- Submeter somente o acréscimo ao GrantGuard existente, inclusive na exclusão
  de um perfil e na criação simples/em lote de usuários sem perfil.
- Ausência do campo continua significando preservar; null/string vazia
  continuam significando retirar, mas exigem alçada para o efeito resultante.
- IDs de perfis devem ser escalares positivos e pertencer à conta atual.
- Serializar alterações de perfil/papel pela conta, com revalidação do ator
  depois do lock e sem query cache. A edição de perfil usa a mesma ordem
  conta → perfil. PATCHes apenas de nome/presença não adquirem esse lock.
- Mutação do nome e associação devem ocorrer na mesma transação; uma recusa
  não deixa uma atualização parcial nem um registro falso de auditoria.
- Preservar contratos e permissões de outros módulos. Nenhuma migration,
  concessão real, mudança no PABX ou alteração de disponibilidade operacional.
- Herança por equipe e elegibilidade explícita serão um incremento separado;
  este guard reutilizará a política efetiva quando ela evoluir.

## Aceite e testes preparados

APIs nativas: retirada própria/alheia acima da alçada negada; retirada permitida
quando o ator detém o resultado; promoção nativa bloqueada; perfil externo
recusado; exclusão de perfil atribuído protegida; exclusão sem acréscimo
preservada; feature desabilitada não altera as regras de outros módulos;
criação simples/em lote sem concessão acima do ator. Testar persistência,
rollback e auditoria, mantendo as suites nativas já aprovadas.

Os testes precisam de Rails/PostgreSQL descartáveis na CI do SHA novo. A
decisão e o checkpoint não equivalem a teste aprovado ou aceite integral F11.

## Diagnóstico nativo do primeiro incremento

CI 44139147817 no SHA e354509f executou 540 exemplos, com duas falhas nos
testes nativos de convites em lote. A transação externa acrescentada fazia
rollback de convites já aceitos, contrariando o contrato de sucesso parcial
existente. Correção: validar cada criação dentro do lock que o loop nativo
já mantém, sem envolver a operação inteira em nova transação. As duas
asserções antigas permanecem; não foram reduzidas nem excluídas.

Os 21 cenários novos de fallback passaram nessa execução. Sete infrações
novas de lint foram identificadas; separar a comparação de efeito do perfil
e ajustar alinhamento, sem supressões. Exigir nova validação do SHA corrigido.
