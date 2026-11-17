# Preservação de perfis nas atualizações parciais de agentes

Estado: aceita para implementação incremental no escopo autorizado; validação pendente.

## Fato observado e impacto

No SHA cfcae689, o módulo Enterprise de AgentsController chama
associate_agent_with_custom_role depois de create/update. O método atribui
params[:custom_role_id] mesmo quando o campo não está presente. O guard de
concessão retorna antes quando o parâmetro é vazio.

A omissão em um PATCH deve preservar o perfil atual: desvinculá-lo pode remover
permissões de outros módulos e acionar o fallback nativo do Call Center.
A primeira correção é restrita ao vínculo omitido; nenhuma capacidade nova,
migração, concessão ou mudança na política global de usuários.

## Contrato da primeira fase

- Campo ausente: manter custom_role_id existente.
- Campo explicitamente informado: preservar o fluxo de validação, escopo e
  atribuição nativos nesta fase.
- Validar com APIs Rails reais a atualização do próprio administrador, de outro
  usuário, disponibilidade, perfis de outros módulos e acesso entre contas.
- Executar também os specs existentes de AgentsController, sem mascarar falhas.
- Registrar a diferença e os resultados no novo SHA.

A correção desta fase NÃO declara resolvidas a remoção explícita de perfil,
o fallback após excluir um perfil, a herança por equipe ou a elegibilidade de
novos usuários. Essas frentes exigem guard de autoridade efetiva e revalidação
transacional próprios; não devem receber concessões automáticas.

Nenhum usuário real ou integração externa será alterado.
