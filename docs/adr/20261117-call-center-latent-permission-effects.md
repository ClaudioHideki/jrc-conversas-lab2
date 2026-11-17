# Call Center: validar concessões latentes e efeitos das dependências

Status: decisão técnica anterior à correção incremental.

A comparação por chaves adicionadas não basta quando visualizar é uma
dependência. Um perfil/equipe pode ter Publicar sem Visualizar. Acrescentar
somente Visualizar, trocar o perfil ou adicionar uma equipe pode então
ativar Publicar. Igualmente, avaliar apenas o resultado efetivo de um usuário
pendente permite armazenar concessões críticas latentes acima do ator.

Preservar os 13 nomes de capacidades, a elegibilidade e os escopos. Exigir
duas comparações: chaves explicitamente acrescentadas e aumento efetivo por
destinatário. Nenhum preview é persistido ou aceito dos parâmetros HTTP.
Usar cópias de modelos/contextos locais e o mesmo GrantGuard/ModulePolicy.

Aplicar à autorização individual, à edição/atribuição de perfil, à edição de
concessões de equipe e à adição de membros pelo fluxo nativo. As verificações
ocorrem antes da persistência, dentro dos locks já existentes, de modo que
um ator não consiga usar a concessão proposta para autorizar a si próprio.
Revogações sem aumento permanecem permitidas pela regra já existente.

Regressões exigidas: tentativa de concessão crítica a usuário pendente;
troca de perfil ativando concessão individual; Visualizar ativando Publicar
em perfil/equipe; inclusão em equipe ativando capacidade de outra origem;
caminhos permitidos quando o ator detém o resultado. Preservar auditoria e
todos os cenários anteriores. Validação nativa do novo SHA é obrigatória.
