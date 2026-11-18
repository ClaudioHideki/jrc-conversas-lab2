# Cockpit — indicadores e contexto autenticado — 18/11/2026

## Estado

Correção candidata temporária, sem execução nativa própria. Não pertence à CI de66fa4f9a em andamento.

## Problema confirmado

O cockpit misturava números da referência visual com contagens nativas: active_calls aparecia como Atendimentos hoje e open_cases como Satisfação. Ausência de dados e tempo médio usavam os exemplos do catálogo visual. As tabelas demonstrativas ficavam acima dos controles reais.

## Decisão

Preservar a estrutura visual e todos os controles reais abaixo dela. Usar a capacidade overviewOnly já existente, manter a biblioteca demonstrativa nas rotas de referência e expor somente indicadores com a finalidade correta: chamadas ativas, retornos pendentes e ocorrências abertas. Valor zero real permanece zero; tempo médio sem fonte permanece desconhecido, com indicação de pendência. Não inventar fórmula, população de atendimento diário ou satisfação.

Reutilizar o contexto de autenticação já empregado no supervisor. Troca de conta, usuário, perfil ou permissões limpa observações e seleção anteriores, solicita nova leitura nativa e rejeita respostas tardias. Revogação/erro numa atualização de retornos também limpa conteúdo antigo. Nenhuma consulta amplia escopo; Account/empresa/unidade continuam validados pelas APIs existentes. Não há operação de PABX ao limpar a interface.

## Validação exigida e limites

Sete Vue direcionados: pendente/erro, rótulos e valores positivos, zero versus ausência, conta anterior, perfil alterado, saída da autenticação e atualização negada. Os quatro Chrome operacionais existentes ganham comparação dos indicadores com o contexto real autorizado e mantêm suas verificações de pausa/persistência/negação. Os140 cenários permanecem obrigatórios.

A consulta backend de contagens não mudou: o modelo nativo confirmado no SHA66fa4f9a possui ended/failed como estados terminais; abandoned não faz parte do enum. Não presumir um bug de consulta a partir de outra versão. Indicadores diários, satisfação e média completos continuam pendentes de fonte e critérios próprios, sem remover funcionalidades reais de pesquisa ou relatórios existentes.
