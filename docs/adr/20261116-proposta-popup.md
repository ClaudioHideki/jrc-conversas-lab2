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
- CI e nova imagem no SHA do incremento ainda devem ser concluídas. Base de código `d650835`, contendo a imagem anterior do produto `c8efa1d6` e seu registro documental.

Não há alteração de contratos de API, regras comerciais, dependências, migrations ou dados. Nenhuma implantação no servidor faz parte desta alteração.
