# Atividade administrativa recente na Central

Estado: implementação preparada na cópia temporária, sem aceite nativo ou visual.
Complementa as figuras 1 e 2; não representa aplicação no PABX.

## Implementação

O painel usa `configurationAudits` com página 1 e cinco itens, no período e
fuso retornados pelo servidor. O endpoint já possui ordenação, paginação,
sanitização, Cache-Control no-store e cobertura atual/histórica. Nenhum
novo endpoint, tabela, contador operacional ou credencial é introduzido.

Cada registro abre a consulta nativa de detalhe, com o Dialog e
ConfigurationAuditDetails existentes. Exibe antes/depois, recurso, ator,
revisão, correlação e a distinção explícita entre registro local e publicação.
O histórico abre o mesmo painel de auditoria e o mesmo recurso, preservando
parâmetros de navegação e limpando filtros antigos de auditoria. Não há
escrita por esse componente.

A entrada só é montada com a capacidade configuration_audit retornada pelo
backend. Falha não vira lista vazia de sucesso. Negação no detalhe limpa os
registros e informa acesso negado. Respostas antigas são descartadas após
troca de conta, fechamento do popup ou desmontagem. A página inteira passa
a usar a fronteira autenticada de conta/usuário/tipo/papel/perfil/permissões,
reutilizando accountMembershipAccess do Cadastro Mestre para preservar todos os campos nativos de acesso, inclusive status e escopos futuros. Somente metadados de presença são excluídos. Logout e troca de perfil
retiram os dados antes de uma nova consulta. O servidor continua autorizando
cada chamada; o estado do navegador nunca concede acesso.

## Testes preparados

Quinze testes Vue: limite/período/fuso/ator, detalhe e fechamento, navegação,
falha e retry explícito, negação sem falso vazio, resposta tardia, troca de
conta, vazio real, capacidade ausente, troca de perfil e logout; resposta privilegiada tardia e negação do servidor após atualização de perfil. O fixture
antigo de AdministrationSection recebe somente o contexto autenticado agora
consumido pela página; não são retiradas asserções.

Os oito cenários Chrome de auditoria já existentes recebem a lista real de
cinco eventos conferida contra a API, detalhe, histórico e prova de ausência
de evento de outra unidade. São mantidos os 112 cenários e todas as provas
anteriores de filtros, paginação, CSV, permissões e revogação. Oito capturas
adicionais devem mostrar a lista e o popup em 1440/390 px e claro/escuro.
Os testes Vue usam mocks e não substituem essas provas com Rails/PostgreSQL.

Lints direcionados locais passaram depois das correções de estilo. Vue,
assets, Chrome, contraste e geometria ainda dependem do próximo SHA e de
runner descartável. Não declarar a figura inteira ou as 23 concluídas.

Alertas do fornecedor, execução, ACK e reversão permanecem dependências
distintas. O painel não usa eventos ilustrativos como dados operacionais.


O mesmo próximo incremento corrige a descoberta do editor de URA pela
permissão configure já exigida em suas APIs; ver ADR de rascunhos locais.
São cinco novos exemplos Rails e quatro cenários Chrome anteriores ampliados,
sem reduzir os 112 nem alterar autorização de publicação. A evidência dos
painéis novos continua pendente. A composição deve preservar todos os
resultados do checkpoint de segurança anterior.

A fronteira também é testada para mudança do status de conta no contexto autenticado sem alteração
das permissões e para ausência de recarga quando só muda a presença.

As nove advertências novas de internacionalização foram resolvidas no componente,
com chaves estáticas e interpolação, sem desativar regras. Componente e seus
15 testes preparados têm zero erros/avisos de lint. ControlDeskPage mantém
os mesmos cinco avisos preexistentes da base, sem apontamentos novos.

## QA subsequente — 18/11/2026

O SHA 699f2c7b aprovou 958 Rails únicos, 16 reexecuções de recarga e 315 Vue. Os 112 Chrome foram executados: 108 passaram; quatro encontraram dois cabeçalhos na verificação de CSS da Central. O seletor passa a exigir o único cabeçalho filho direto, mantendo a verificação de fundo real. Não atribuir aprovação integral a esse SHA.

A revisão das capturas de ac85d6eb encontrou página 1 de 0 em estados sem registros. A correção conserva o total real, omite a paginação inexistente, limpa páginas antigas ao carregar referências e diferencia vazio de erro e de unidade ainda não selecionada. Dois testes Vue novos e os quatro cenários reais de retirada de equipe verificam a ausência da página impossível; novo gate obrigatório. Nenhuma autorização ou contrato de paginação da API foi alterado.

Revisão estática subsequente encontrou também duas leituras de cor via evaluate usando o seletor antigo, depois da primeira asserção. Ambas passam a apontar para o mesmo header direto. Todas as três verificações de CSS/tema continuam presentes; 2c6971b8 ainda requer o resultado da CI e não é declarado aprovado por antecipação.

CI 44272597974 confirmou 958 Rails únicos, 16 reexecuções de recarga, 317 Vue e zero novas infrações Ruby. Os mesmos quatro cenários Chrome pararam na primeira leitura evaluate, linha 711, ainda com seletor amplo; os outros 108 passaram. Artefato 14415097723, SHA-256 e8f84090258dfe6aac95dc95661746a934a22ff3b557ea58c6b7d4f72c445e73. A correção completa requer novo SHA e não usa o resultado parcial como homologação.
