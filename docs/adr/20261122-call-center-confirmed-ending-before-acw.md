# Confirmação do motivo antes de concluir o ACW

Estado: decisão de negócio aprovada em 22/11/2026; implementação isolada preparada e testes leves aprovados. Validação nativa e homologação Chrome pendentes.

## Decisões aprovadas

As automações usam as permissões atuais do agente que concluiu o atendimento, revalidadas em cada execução e tentativa. Responsável pelo registro de destino e usuário executor são conceitos distintos. Não existe fallback para administrador, usuário técnico ou permissões do autor da regra.

Para automações do fim da chamada, o agente confirma explicitamente o motivo antes da execução. Essa confirmação mantém o ACW aberto até concluir o formulário. Salvar um rascunho não confirma o motivo e não autoriza criar registros em outros módulos.

## Contrato incremental

Reutilizar a qualificação, seu catálogo congelado, o rascunho, a revisão esperada e o formulário nativos. Não criar outro atendimento, catálogo de motivos ou motor de pausas.

Adicionar uma confirmação opcional e imutável, vinculada à qualificação nativa e ao seu ator original. A confirmação só aceita motivo registrado na versão já congelada para aquela chamada. Fluxos antigos sem confirmação preservam seu comportamento. Nenhum catálogo ou configuração real será ativado por esta alteração.

A nova operação autentica novamente o usuário, verifica elegibilidade e operação no Call Center, acesso atual à chamada e autoria da qualificação. Conta e usuário derivam do contexto autenticado. O corpo não concede acesso por IDs de conta, agente, empresa ou unidade.

Salvar o rascunho completo e a confirmação na mesma transação e sob os bloqueios nativos de conta e qualificação. Preservar notas, resultado e respostas, inclusive formulários incompletos. Usar chave de idempotência e digest do conteúdo para reconhecer uma resposta perdida sem duplicar a confirmação nem aceitar outro conteúdo com a mesma chave.

Depois da confirmação, o motivo fica fixo também nas APIs e no banco. Notas, resultado e respostas continuam editáveis enquanto o ACW permanecer aberto, segundo as validações atuais. Uma futura correção do motivo exigirá fluxo explícito e auditado; não introduzir alteração silenciosa de uma classificação que possa ter originado outros registros.

Registrar origem, motivo, versão do catálogo, ator e horário no servidor. Não armazenar notas ou respostas completas na confirmação ou em logs. Preservar a identidade histórica quando a qualificação for removida pelo ciclo de vida nativo: o vínculo vivo pode ser nulo, mas o ID e a evidência originais permanecem imutáveis. A nova tabela não altera o ciclo de conta: as FKs históricas de atendimento continuam bloqueando a retirada da conta enquanto essas evidências existirem. A cascata declarada da nova tabela não autoriza remover os impedimentos nativos.

## Limites

A confirmação não conclui a qualificação, não resolve conversa, não muda disponibilidade, não libera chamadas e não aplica pausa. Uma pausa aprovada continua aguardando o fim da chamada e a conclusão efetiva do ACW.

Esta evidência de classificação não concede permissões em CRM, Service Desk ou Projetos. O motor de automações, seus recibos por destino e o contexto corporativo histórico verificável continuam sendo incrementos separados. Não inferir empresa ou unidade histórica a partir do cadastro atual. Não anunciar automação executada somente porque o motivo foi confirmado.

Nenhum comando PABX, canal externo, concessão real, publicação ou deploy faz parte deste incremento.

## Validações obrigatórias

- Migração aditiva vazia; instalação, atualização, reexecução e recarga do schema; preservação das migrations e SQLs anteriores.
- Proveniência, FKs, unicidade, imutabilidade, remoção nativa da qualificação e ciclo de conta em PostgreSQL real e sintético.
- Confirmação, repetição idempotente, chave com conteúdo divergente, revisão vencida e concorrência.
- Conta ou qualificação de outro agente, perda de acesso, elegibilidade ou perfil e troca de contexto durante a requisição.
- Catálogo congelado, motivo inválido ou ausente e compatibilidade com qualificações antigas.
- Preservação do rascunho e formulário obrigatório incompleto; rejeição de mudança do motivo por APIs e SQL após confirmar.
- Confirmação mantém ACW, bloqueio operacional e pausa pendente; somente a conclusão nativa libera suas transições.
- Interface e confirmação explícita em Chrome 1440/390 px, claro/escuro; persistência após recarga e tratamento de falha sem envio duplicado.

Execução nativa, build protegido e Chrome serão feitos exclusivamente no workflow isolado autorizado. A CI já ativa do checkpoint de contraste não será reiniciada nem receberá silenciosamente este código.
