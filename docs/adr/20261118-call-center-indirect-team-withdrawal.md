# Retirada de equipe e impacto no último agente configurado

Status: implementado em preparação; lint frontend dirigido aprovado. Testes Rails, Vue e Chrome deste incremento ainda não executados.

## Decisão e limite

A decisão aprovada exige confirmação explícita do gestor, revisão e auditoria, sem aprovação formal ou publicação no PABX. Ela já é aplicada à retirada direta de QueueMembership. Este incremento cobre a retirada indireta pelas operações nativas POST/PATCH/DELETE de TeamMember, sem excluir pessoas ou criar outro cadastro de equipes.

A confirmação é necessária apenas quando uma fila ativa com agentes configurados elegíveis passa a não ter nenhum. Presença online, estado provider_pending e disponibilidade externa não são prova de elegibilidade configurada. Supervisor sem participação não conta como agente. Operações desabilitadas, manutenção de fila já vazia e remoções sem esse impacto preservam os direitos nativos de TeamPolicy.

## Reutilização e autorização

- ConfiguredQueueEligibility concentra os critérios que a retirada direta já utilizava: elegibilidade individual explícita, negações, papel/perfil/permissões herdadas, autenticação atual, cobertura nativa, papel de agente e janelas de vínculo/fila/unidade. A retirada direta reutiliza o mesmo serviço.
- TeamMembershipProjection é uma projeção interna, somente de leitura, de um Account/Team e usuários pertencentes à conta. CurrentStructureScopes, CorporateCoverage e OrganizationalScope recebem a projeção opcional; sem ela o caminho nativo permanece igual. Os predicados existentes de origem ativa e contenção continuam intactos. Não existe parâmetro HTTP para conceder essa projeção.
- TeamRosterPreview compara o conjunto completo antes/depois sem adicionar/remover membros temporariamente. Reutiliza PermissionSources para permissões prospectivas e as coberturas acima. Fontes diretas/outras equipes e substituições atômicas continuam válidas. Associação a equipe não cria concessão, elegibilidade ou participação em fila.
- TeamScopeActivationGuard e TeamAssignmentGuard continuam executando antes da nova revisão. A retirada exige o TeamPolicy nativo. Caso esvazie uma fila, exige configure e acesso a todas as filas afetadas pelo AccessScope atual; nenhuma lista parcial de filas fora do escopo é revelada.

## Revisão, transação e auditoria

O recibo assinado dura dez minutos e vincula conta, AccountUser/usuário do gestor, equipe, ação, hash das listas completas antes/depois, conjuntos de agentes elegíveis e revisões das filas/unidades. Somente confirmed=true literal é aceito. Não é uma concessão de acesso. O servidor recalcula os fatos e reautoriza a cada requisição sob o mutex nativo de Account.

A auditoria sanitizada usa o recurso Queue e os snapshots corporativos antes/depois existentes. Identifica a retirada pela equipe e a distingue de uma alteração direta do vínculo. Guarda apenas o hash do recibo, nunca o token ou o catálogo completo de pessoas. A gravação obrigatória é feita dentro da transação de Account, antes de o controlador nativo renderizar a resposta. Se ela falhar a alteração não começa; se a ação nativa lançar erro, toda a transação é revertida.

As atribuições QueueMembership e os grants armazenados são preservados. A mudança de autoridade decorre da composição atual das fontes nativas, não de apagar histórico.

## Interface existente

O mesmo componente/composable atende os editores existentes do Control Desk, CRM/Estrutura e Configurações/Equipe. No Control Desk a revisão aparece dentro do popup já aberto; nos dois editores de página, um Dialog nativo abre a revisão para que ela não fique oculta abaixo da rolagem. Nenhuma confirmação é automática. O conteúdo é vinculado ao rascunho e à autoridade atual, fica só em memória e é invalidado inclusive em troca rápida A→B→A e cancelamento. Uma falha de transporte preserva o rascunho; negativas limpam o impacto privado. O Vuex mantém a resposta HTTP para o editor receber o 409 estruturado e armazena os membros na chave da equipe correta.

Apenas en/jrcContactCenter.json recebe os novos textos, conforme AGENTS. Um erro preexistente de texto literal no botão de remover membro do CRM foi corrigido com o ícone nativo de fechar e o rótulo acessível existente. Não foram alteradas regras de lint.

## Verificação preparada

- Projeção nativa: fontes diretas/alternativas, reativação prospectiva sem escrita, conta e contenção, sem grants implícitos.
- Serviços/HTTP: retirada por substituição e exclusão de vínculo, perda funcional/corporativa, negação individual, janelas, fila inativa, vários agentes/filas, troca por substituto com origem dormente autorizada, conta/unidade negadas, recibos falsos/expirados/alterados e repetição idempotente.
- Concorrência: requisição real comprovadamente esperando Account FOR UPDATE; revogação de configure e revisão de fila modificada durante a espera.
- Vue: recibo, negação, troca de contexto/seleção/perfil, rede, editores nativos, transporte e identidade no Vuex.
- Chrome: 152 cenários exigidos, preservando os 148 anteriores. Novo fluxo nativo de revisão explícita, negativa, persistência/recarga e auditoria em desktop/celular, claro/escuro, com dados sintéticos e CSS novo.

O lint local dirigido passou em quatorze arquivos, zero erros/avisos novos; avisos preexistentes foram comparados à base. Isso não substitui Rails, Vue nem Chrome. A execução anterior 44435975247 passou 1205 Rails distintos, 16 recargas e 534 Vue, mas uma infração RSpec/MatchArray bloqueou assets/Chrome; a correção isolada está em 3f8f2bc8 e possui CI própria. Não reutilizar esse resultado como aceite do novo incremento.

## Pendências preservadas

A exclusão da entidade Team inteira exige auditoria separada de dependências/FKs e não é apresentada como coberta por esta revisão de TeamMember. Hierarquia de supervisores, estado operacional próprio da equipe e disponibilidade/ACK externos continuam pendentes. As 23 figuras e as etapas 0–2 não estão concluídas. Nenhum comando PABX, imagem, merge, publicação ou deploy foi autorizado por esta implementação.

## Revisão de IDs e primeiro gate nativo — 19/11/2026

O SHA 2c8b10f0 foi executado na CI 44448633679. A recarga do schema passou (16 exemplos); o bloco principal executou 1.100 exemplos com uma falha: após destruir a fonte, a associação já carregada do Account não foi recarregada antes da expectativa de vazio. A checagem de ausência de cobertura passou. O teste agora recarrega essa associação para consultar o estado persistido, mantendo a expectativa de nenhuma fonte criada. Cinco infrações Ruby novas foram corrigidas sem exclusões ou mudanças globais de lint. As etapas subsequentes ficaram bloqueadas; o incremento não está homologado.

Na revisão do caminho nativo encontrou-se diferença entre a prévia (IDs canônicos) e a subtração de arrays no controller de equipes (parâmetros brutos). Um PATCH com o mesmo usuário em formato texto podia parecer uma operação sem mudança para a prévia, mas remover o vínculo na ação nativa. O overlay Enterprise agora normaliza os IDs já validados como pertencentes à conta, dentro da transação e antes dos guardas e da ação nativa. Dois testes HTTP preservam o mesmo ID do vínculo para a operação sem mudança em texto e para a mistura texto/número. Não se concede acesso nem se altera o contrato de retirada real. Nova CI necessária para provar o resultado.

## Gate completo até a auditoria visual — c0e20792

A CI 44455878332 confirmou 1.270 exemplos Rails distintos, 16 de recarga do schema e 573 Vue; todos com zero falhas e pendências. O lint Ruby não apresentou infrações novas; o frontend, o build fresco protegido e o bootstrap real de 15 cards passaram. O Chrome passou 148 dos 152 cenários, com quatro falhas da mesma identidade lógica (uma por viewport/tema), sem skips, flaky ou erros externos.

A única falha está na última conferência do comprovante: o seletor global encontrou tanto a prévia da página quanto o conteúdo do diálogo Detalhes do evento. O backend retornou um único evento de revisão, já confirmado pelas verificações anteriores do mesmo cenário; não houve prova de duplicidade de registros. A árvore de acessibilidade e as capturas reais desktop claro/celular escuro confirmam o diálogo e seu conteúdo. A correção restringe a busca ao diálogo pelo nome acessível exato, exige uma única seção, rola o conteúdo e confere visibilidade e o mesmo ID da equipe. Nenhuma asserção anterior, gate ou timeout foi removido.

Artefato 14499601646, SHA-256 421fc1273f9de3ec3a28473935c25adb84f8dca4edfc9b010941df42e0af5e20. O gate continua reprovado até uma nova execução no SHA corrigido; acceptance.json não foi gerado. O incremento seguinte de rascunhos ACW permanece separado e não é validado por essa execução.
