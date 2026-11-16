# Perfis nativos: atualização transacional e limites de contrato

Status: correção compatível em revisão; ampliação de autoridade não implementada.

A base 1834971c e a CI 43938106822 preservam 386 Rails, 178 Vue e 44 Chrome. O incremento adiciona a recarga sob with_lock antes do cálculo de novas concessões, mantém a autorização nativa e retorna 404 para perfil de outra conta. Uma revogação concorrente não pode ser desfeita pela leitura antiga usada pelo GrantGuard. O teste usa PostgreSQL e sessão HTTP reais; os testes não consultam produção.

As alterações de capacidades CC usam Enterprise::AuditLog na transação original, com ator/Account e listas antes/depois filtradas. Nenhuma descrição, credencial, token ou configuração arbitrária é copiada. O log não é uma base de concessões. Alterações de nome/descrição e configurações de unidades/filas ainda não estão cobertas por esta trilha específica.

O popup reutiliza CustomRoleModal, API, store e SnackbarContainer existentes. Apenas a origem Call Center opta pelo erro em português; outros módulos mantêm seus contratos. A origem Call Center exige revisão explícita do diff de capacidades antes da confirmação; editar os dados invalida a revisão. Formulário e seleções permanecem disponíveis quando a API nega uma concessão. Os 44 cenários Chrome anteriores permanecem, acrescidos de criação e negação em quatro combinações.

## Propostas que precisam de aprovação de contrato

1. Herança: Team/TeamMember não possuem grants. CustomRole define capacidades de AccountUser; escopos corporativos e de fila continuam restrições independentes. Criar herança exige definir fonte de concessões, precedência de negação, revogação e alcance entre módulos. Não propagar automaticamente permissões de membros ou supervisores.
2. Conflito de formulários: o payload atual não recebe revisão esperada. with_lock não detecta sozinho uma edição visual antiga. Propor token de revisão atômico/If-Match e resposta 409, com compatibilidade explícita para clientes existentes; decidir quando rejeitar clientes sem revisão. Não usar GET antes de PATCH como falso controle de concorrência.
3. Exclusão de perfil: dependent:nullify é o comportamento nativo e pode restaurar fallback de acesso. A política de reassociação/bloqueio precisa de análise multi-módulo antes de alterá-la; este popup não oferece exclusão.
4. Team corporativo e supervisor principal não existem no modelo atual. Não inventar status, unidade, supervisão hierárquica ou vínculo Team–Queue dentro de settings sem contrato.

A matriz das 23 figuras mantém pendências 0–2 separadas de fases posteriores. Não há declaração de conclusão integral, publicação, deploy nem homologação externa. Conector PABX possui consultas/sincronização CDR e contratos mapeados; sucesso de CDR não prova publicação de inventário/URA nem ACK remoto. Guardas SQL Supabase em banco descartável não provam bucket/RLS externo.

5. Elegibilidade: ModulePolicy#native_role? preserva o acesso legado de vínculos sem CustomRole. O Word exige que cadastrar usuário não ative automaticamente o Call Center. A correção depende de uma política/migração de elegibilidade que preserve acessos existentes, sem novos grants implícitos. Permanece pendente nas etapas 0–2.

## Correção de escopo confirmada no contrato existente

O popup já proíbe edição global sob cobertura restrita. A API nativa passa a conferir a mesma CorporateCoverage em perfis que envolvam capacidades CC, inclusive nome, retirada e exclusão, sob a transação/lock da atualização. Perfis sem CC e contas sem estrutura corporativa configurada mantêm a política nativa. Não há parâmetro de unidade concedendo acesso nem novo motor de concessões. Cinco exemplos Rails e a identidade Chrome de limite corporativo cobrem o administrador nativo limitado a uma unidade, o Group sintético explícito e a preservação de perfis de outros módulos.

## Elegibilidade de vínculos locais

Fila inativa não aceita novos vínculos, mudança de alvo ou reativação pelo endpoint existente. Autorizações de fila/usuário continuam sendo verificadas antes da regra de estado. Desativar um vínculo já existente permanece permitido para evitar bloquear sua retirada segura. Não se apaga histórico nem se infere distribuição real: a confirmação PABX continua separada. O popup exibe o erro usando os rótulos pt_BR já existentes e mantém campos e seleções para uma nova tentativa. Os 52 cenários Chrome são preservados; o cenário de participantes é ampliado com rejeição, recuperação em fila ativa, desativação e reativação negada. Quatro exemplos Rails adicionais cobrem o contrato sem mocks de banco.

## Corrida do filtro após salvar

Na CI 43962051059, três projetos Chrome chegaram à busca sem units_q: a consulta da lista era aguardada antes de emitir changed. O painel começava sua recarga depois e desmontava a seção quando o usuário já digitava. A notificação passa a ocorrer imediatamente após a confirmação da persistência e o fechamento do popup; em seguida ocorre a consulta da lista. O painel mantém sua limpeza/revalidação original de dados, contas e permissões. Dois testes Vue controlam uma Promise pendente para provar a ordem em recursos e perfis. As 52 identidades Chrome e a contagem exata de uma linha filtrada permanecem, sem aumentar timeouts ou inserir retries.
