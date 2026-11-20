# Autenticação atual em atribuições do Call Center —20/11/2026

Status:correção interna preparada; execução nativa e visual pendente.

As figuras3/12 proíbem novos vínculos a usuário inativo. O grant individual de elegibilidade e a presença online não comprovam que o usuário ainda possa autenticar. A seleção administrativa existente já sabe desabilitar opções indisponíveis; sua API agora combina o grant explícito com active_for_authentication? do User nativo, sem alterar qualquer grant.

A API de participação/supervisão revalida esse estado no mesmo fluxo nativo de configuração, inclusive depois de aguardar locks. Um vínculo antigo conserva a pessoa e pode ser desativado com segurança; reativação, novo vínculo e troca para destinatário indisponível continuam bloqueados. Não se atribuem fila, ramal ou acesso por papel/nome.

A reautorização da configuração também recarrega o próprio User autenticado após os locks. Um pedido que começou válido não pode gravar uma unidade, fila ou vínculo após o usuário perder autenticação. Isso segue a checagem já usada nas operações do atendimento; não muda a autenticação ou os módulos externos ao Call Center.

Três testes concorrentes usam o PostgreSQL descartável e barreiras nativas. A alteração de autenticação ocorre somente depois de pg_stat_activity comprovar a espera pelo lock, ainda dentro da transação que o detém. O padrão antigo das demais corridas é preservado. Não há sleep para presumir que a operação começou, mocks de resposta ou alteração de usuário real.

O Chrome exige53percursos em cada uma das quatro combinações1440/390 eclaro/escuro:212no total, preservando os208anteriores. O novo percurso usa User não confirmado real no banco sintético, prova o grant retido, recusa forçada pela API, desativa pela UI, recarrega e recusa reativação preservando o rascunho. O fixture falha se o destinatário ainda puder autenticar. Nenhum comando PABX ou publicação é executado.

A correção independe da regra de inativação de equipes, ainda em decisão. Native Team, permissões herdadas e fontes corporativas permanecem intactas neste incremento.

## Validação nativa concluída

SHA86c4ad536c5cfdcb091498ae4552ad2b8a143773,CI44679530987:1.808Rails distintos,81reexecuções schema,870Vue,212Chrome,zero falhas/pendências/erros externos.308capturas com hashes conferidos e12revisadas visualmente. Artefato14606540165,SHA-256d174620ae05e9ce122ab38a3c77490d7ab0c8565db845618299d7afeb555b8f8. Os estados preparados acima registram o histórico;este incremento está validado,sem concluir as23figuras.
