# Autenticação atual na administração de permissões — 20/11/2026

Status: preparado; testes nativos deste complemento ainda pendentes.

O serviço nativo AccessAuthorization já revalida papéis, cobertura, alçada, revisão e efeitos da concessão dentro do mutex de Account. Faltava recarregar o User autenticado e exigir active_for_authentication? nesse ponto. Um objeto obtido no início de uma requisição podia continuar autorizado depois de o usuário perder autenticação durante a espera.

A correção acrescenta somente essa verificação antes das ramificações nativas de SuperAdmin e administrador. Um usuário ainda ativo mantém exatamente as mesmas regras; nenhum papel, grant, escopo ou vínculo é criado, removido ou deduzido do cargo. Não se modifica a autenticação de outros módulos ou o controle de revisão.

Um teste preserva deliberadamente o objeto antigo em memória, altera o User por outro objeto nativo e exige recusa sem persistir o grant. Outros dois usam o banco descartável, transação e pg_stat_activity para comprovar espera real pelo lock antes de retirar autenticação. Cobrem concessões individuais e por equipe, com snapshot integral dos grants antes/depois.

Os testes e esta alteração não integram o SHA 76c37bbe já em CI. Serão validados no checkpoint deste incremento; as evidências anteriores não serão atribuídas a este complemento. Não há mudanças de interface, novas operações externas, ativação de alçadas, publicação ou deploy.
