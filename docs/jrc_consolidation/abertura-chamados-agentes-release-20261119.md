# Abertura interna por agente e destinatário — 19/11/2026

Produto: `ab6bba04749fc38276c6465968b9e757aa7f93c2`.
Branch: `codex/abertura-chamados-agentes-20261119`.
Base: `e466d9274e51231d2157078a66ec1c51ec60fe62`, que conserva a imagem
`f494fd38dd62929303279d39b4591372ac72e607` observada no HTML público do JRC
em 19/11. A main permaneceu em `e6bd4cc9418b3522378a460bb97814b700f39123`.

## Resultado

- O agente abre o chamado em seu próprio nome e escolhe o destinatário ativo
  na unidade selecionada, incluindo pessoas de outros departamentos.
- A escolha explícita usa a fila de triagem quando compatível; caso contrário,
  usa a fila/equipe do destinatário ou atribuição direta. Revalida unidade,
  Account, ação, atribuição manual e restrições explícitas no servidor.
- O solicitante interno usa exclusivamente a identidade autenticada. O contato
  pessoal da empresa interna não exige acesso ao diretório comercial para abrir
  em nome próprio. A classificação de pessoa e as fronteiras de conta permanecem.
- A leitura do módulo dispensa a validação do responsável/observador antigo.
  O fluxo sem destinatário explícito conserva as validações legadas. O observador
  só é registrado se puder ver o chamado no destino final.
- Uma tela negada oferece Novo chamado; a navegação verifica novamente a ação
  e recarrega a sessão. Uma recusa real do servidor continua bloqueada.
- A lista de destinatários só é projetada quando a unidade permite criação.

Decisão e limites: [ADR0008](../adr/0008-abertura-interna-por-destinatario.md).

## Imagem

```text
ghcr.io/claudiohideki/jrc-conversas-lab2@sha256:51eda0b109d240ed5a8491238065fc0bdee24c475deb9f6911e1fbeafe8c791b
```

Tag de referência:

```text
ghcr.io/claudiohideki/jrc-conversas-lab2:sha-ab6bba04749fc38276c6465968b9e757aa7f93c2
```

## Verificações

- Local: 51 testes Vue em sete arquivos, cobrindo escolha de pessoa, ausência de
  padrão, recuperação de rota, negação real, navegação e entradas por Account.
- [Validação integrada 44573517512](https://github.com/ClaudioHideki/jrc-conversas-lab2/actions/runs/44573517512):
  1309 exemplos Rails principais, gate autenticado de estabelecimentos com dois exemplos, concorrência em três lotes de 21 + 2 + 2 exemplos e guards de migrations aprovados; 144 arquivos/1622 testes Vue, compilação real e 24 cenários no navegador, sem falhas ou pendências.
- [Build e publicação 44577404793](https://github.com/ClaudioHideki/jrc-conversas-lab2/actions/runs/44577404793):
  três jobs aprovados, regressões adicionais WhatsApp e frontend, gates puros preservados, 2762 testes Vue no job de construção, imagem real e conferência de conteúdo/revisão/plataforma; smokes de aplicação e worker aprovados antes e depois da publicação por digest.
- Manifesto, plataforma linux/amd64 e label da revisão exata conferidos
  independentemente no GHCR por metadados, sem baixar camadas no desktop.

As suítes se sobrepõem e não representam totais somáveis. O primeiro run completo
executou 1309 exemplos com uma expectativa nova de 403 que foi corrigida para 404,
mantendo a ocultação da unidade e a ausência de criação. O run seguinte aprovou
Rails/concorrência e encontrou somente cinco diferenças de formatação no Vue;
restaurado o formato original do componente. Nenhuma regra de lint foi dispensada.

## Aplicação e aceite

No Dokploy, substituir a referência `image:` da base compartilhada do Compose
pelo digest acima, salvar e implantar. Aplicação e worker devem usar essa mesma
revisão. Após concluir, atualizar a página com `Ctrl+Shift+R`.

Na sessão do Ronald, abrir Novo chamado, selecionar a empresa/unidade e um agente,
preencher assunto e descrição e confirmar. Conferir o número criado, responsável
persistido e acesso do destinatário ao chamado. Os testes de criação usam banco
descartável e identidades sintéticas; não comprovam o aceite dessa sessão real.

Vínculo ativo e permissões nativas do Ronald foram conferidos na interface
administrativa; não se observou o endpoint exato que recusou sua sessão.
Nenhuma permissão produtiva foi alterada. Sem migration nova, envio real, backup,
dump, restore, merge em main ou implantação nesta etapa. O commit de evidências
posterior altera documentação; a imagem corresponde ao SHA do produto acima.
