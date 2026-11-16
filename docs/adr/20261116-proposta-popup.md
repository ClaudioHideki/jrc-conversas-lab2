# Detalhes da proposta em popup — 16/11/2026

Estado: Aceita. O usuário solicitou abrir e fechar os detalhes da proposta como popup, mantendo o acesso à lista.

## Decisão

Substituir o painel absoluto que ocupava toda a área do CRM por um `dialog` modal nativo, centralizado sobre a página, com fundo escurecido e dimensões limitadas ao viewport. O conteúdo comercial continua no mesmo componente: cabeçalho e ações, formulários, itens, resumo e rolagem interna.

A abertura usa `showModal`, como o Dialog do sistema, para aproveitar a camada modal e o controle de foco do navegador sem alterar o componente compartilhado. O fechamento por X, Esc e clique no fundo usa o mesmo fluxo de preservação de rascunhos. Eventos de fechamento de janelas filhas não fecham a proposta. Falha ao carregar, troca de Account/papel e desmontagem também fecham o dialog.

## Aceite e evidências

- Abrir pela lista ou por `proposalId`, fechar por X/Esc/fundo e reabrir.
- Preservar PDF autenticado, envio, edição, rascunhos, permissões e invalidação de respostas tardias.
- Testes existentes dirigidos: 46 aprovados em quatro arquivos; o cenário de PDF verifica também a abertura nativa, fechamento por Esc/fundo/X e reabertura.
- Validador de fontes: três arquivos aprovados; 336 timestamps de migrations, nenhuma migration nova.
- ESLint: zero erros; os avisos restantes pertencem ao formulário preservado. Os mocks de dialog usam funções nomeadas.
- Base de código `d650835`, contendo a imagem anterior do produto `c8efa1d6` e seu registro documental. O título do popup permanece disponível também durante o carregamento por link direto.

Não há alteração de contratos de API, regras comerciais, dependências, migrations ou dados. Nenhuma implantação no servidor faz parte desta alteração.

## Publicação verificada

- Produto: `5d57f3ce0783e00709a2c1e246aaa62c9a2ec07d`.
- Tag: `ghcr.io/claudiohideki/jrc-conversas-lab2:sha-5d57f3ce0783e00709a2c1e246aaa62c9a2ec07d`.
- Referência exata: `ghcr.io/claudiohideki/jrc-conversas-lab2@sha256:62cf14c7cbdaeea185f740951a55267687e60c71b253fdcff17ce3b1c9e0f419`.
- [CI 43954203225](https://github.com/ClaudioHideki/jrc-conversas-lab2/actions/runs/43954203225): três jobs aprovados no SHA do produto.
- Frontend: 295 arquivos, 2.752 testes aprovados; Rails: 168 exemplos sem falhas. Relacionamento/Operações puros: 92 testes, 483 assertions, zero falhas/erros/skips.
- Sintaxe, integridade e lint dos gates aprovados; Linux/amd64, revisão interna, arquivos de produto e assets compilados conferidos.
- Rails/Sidekiq e transporte sintético testados antes do push e novamente na imagem publicada por digest.
- Manifesto consultado independentemente no GHCR pelo Docker do desktop; as camadas novas não foram baixadas no disco local.

A execução `43953422601` foi cancelada como substituída antes da publicação, para incluir o título acessível durante o carregamento. A imagem final preserva a remoção do filtro por segmento e não inclui implantação no servidor. Este registro documental posterior mantém o SHA de origem do produto explícito.
