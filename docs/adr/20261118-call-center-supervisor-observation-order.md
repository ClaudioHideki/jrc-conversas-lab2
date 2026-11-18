# Supervisor: ordem das leituras e descarte de autoridade antiga

Estado: correção preparada em 18/11/2026; novos testes nativos ainda pendentes.

## Risco encontrado no código

SupervisorPage inicia setInterval assíncrono sem sinal de leitura em andamento. generation protege troca de conta/recarga, mas duas consultas periódicas da mesma geração podem terminar fora de ordem. A rejeição do supervisor limpava o snapshot, mas conservava nomes das unidades carregadas anteriormente. A página observava somente accountId, não a troca de ator ou de permissões do perfil autenticado.

## Correção incremental

Serializar somente as consultas periódicas; conservar o intervalo existente. Usar o perfil autenticado nativo na identidade da leitura (conta, ator/tipo, papel, perfil e capacidades). Mudanças invalidam respostas anteriores e recarregam os dados. Contexto de autenticação removido limpa as observações e não inicia outra consulta. Durante a leitura, o indicador informa carregamento. Rejeição descarta também a lista de unidades; a consulta periódica renova essa lista pela mesma API autorizada já utilizada na carga inicial. Nenhuma política ou grant é alterado. Mudanças de cobertura que não geram outro perfil continuam sendo aplicadas nas leituras autorizadas; não prometer revogação instantânea por websocket.

Os estados/tipos de unidade exibidos passam a usar traduções existentes; unidade inativa recebe estado visual correspondente. Não há estado operacional inventado.

## Aceite preparado

Quatro Vue: leitura lenta não se sobrepõe; resposta do perfil anterior não restaura dados; erro descarta nomes antes autorizados; autenticação removida limpa observações. O caso do inventário também verifica a apresentação em português.

Chrome: quatro novos projetos, com observador e administrador sintéticos exclusivos nas contas de URA, cobertura corporativa explícita em A e zero chamadas reais. A tela deve mostrar uma unidade autorizada; o administrador revoga a elegibilidade, o próprio polling recebe 401 e remove métricas/inventário sem recarregar a página. Rota forçada passa a negar após recarga. O administrador restaura o valor original em finally e a API confirma leitura autorizada. Não criar grants reais ou ampliar os dados das 96 provas antigas para satisfazer uma expectativa.

O gate passa a exigir 112 identidades Chrome: 96 anteriores, 12 de URA e quatro novas de revogação em uso. Resultados do SHA anterior não comprovam esta alteração. Permanece proibido fornecedor real, Docker, merge ou produção.
