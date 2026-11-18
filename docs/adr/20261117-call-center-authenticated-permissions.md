# Permissões efetivas do Call Center no perfil autenticado

Validação do incremento: cf040419, CI 44203813534, 641 Rails/250 Vue/96 Chrome e 120 capturas verificadas. O aceite é interno e sintético; limites externos permanecem.
Status: implementação incremental autorizada; validação nativa e visual pendentes.

## Problema e evidência

A política do Call Center já reavalia elegibilidade, perfil, equipes da conta e negações individuais. O perfil autenticado, porém, serializa AccountUser#permissions. A extensão Enterprise retorna os valores brutos do perfil. O menu e as rotas também aceitavam o papel administrator/agent, mesmo com acesso ao Call Center negado. Assim, a API protege a operação mas a navegação pode omitir herança válida ou oferecer uma entrada negada.

Revisão concorrente: AccountUser e Sidebar são idênticos entre 7011dac7 e a main d3d66232. As mudanças próprias anteriores em routes/Layout serão preservadas. Nenhuma linha da main será incorporada.

## Decisão e limites

- Normalizar somente as treze capacidades CC em AccountUser#permissions, depois da extensão Enterprise, usando a mesma ModulePolicy com usuário e conta do vínculo. Preservar integralmente os outros módulos e os marcadores nativos de papel.
- Não modificar permissões persistidas, perfis, elegibilidade ou coberturas. Não criar permissões por título/cargo. Não ampliar o fallback legado: a política existente continua sendo a autoridade.
- Menu/rotas CC exigem a capacidade efetiva específica. Relatórios e gravações usam capacidades distintas; configurar não ultrapassa uma negação de relatório/gravação. O supervisor requer supervise, como sua API nativa.
- Não alterar o middleware, as permissões ou os eventos compartilhados dos outros módulos. A API continua reautorizando cada chamada; um perfil obtido novamente reflete as alterações. Atualização em tempo real de menus em outras sessões não é alegada.
- Exercitar o GET autenticado real do perfil, inclusive herança, negação, remoção, elegibilidade, conta estrangeira e preservação de permissões não CC. Exercitar os consumidores nativos de rotas e a navegação no Chrome sintético, sem respostas de autorização inventadas.

## Aceite

Testes Rails e Vue, lint incremental, migrations preservadas e cenários Chrome desktop/celular claro/escuro no SHA do incremento. Nenhum teste simulado substitui a integração autenticada. Backend e cliente devem negar após revogação; nomes de equipes não concedem cobertura corporativa nem acesso PABX administrativo.
