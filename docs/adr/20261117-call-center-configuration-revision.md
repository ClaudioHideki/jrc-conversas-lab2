
# Revisão esperada nos cadastros administrativos do Call Center

Estado: aceita para implementação compatível dentro do escopo autorizado; validação pendente.

## Contrato e impacto antes da implementação

A revisão de perfis já está validada em 80632726. Unidades, filas e vínculos
ainda podem receber edições obsoletas dentro do mesmo escopo. A serialização
transacional e a auditoria não equivalem a uma precondição do formulário.

Propõe-se um campo de resposta revision, sem autoridade, calculado do estado
persistido; GET individual autorizado para recarga; e expected_revision opcional
na raiz do PATCH. Clientes antigos sem o parâmetro mantêm o contrato. Clientes
que o enviam precisam de token não vazio (428); conflito de estado retorna 409
sem mutação nem auditoria de sucesso. A comparação ocorre sob bloqueio e somente
após validar o acesso atual ao registro e seus vínculos.

O token inclui a classe e atributos canônicos, com timestamps de microssegundos;
não expõe settings privados. Hashes com ordem diferente não devem criar
conflitos artificiais. Conta, unidade, cobertura corporativa e capacidades
continuam sendo validadas pelas políticas existentes, nunca pelo token.

O formulário atualizado enviará sempre a revisão capturada em edição.
Conflito preserva o rascunho, impede repetição silenciosa e exige recarga para
comparação e confirmação explícita. Nenhum dado digitado será substituído
automaticamente. Criação não recebe precondição de edição.

Sem migrations, novas capacidades, concessões, efeitos PABX ou mudanças nos
demais módulos. A API nativa de equipes permanece separada; não anunciar
proteção de revisão de equipes antes de existir contrato e validação próprios.

## Validação exigida

- APIs reais: token estável, corrente, vazio, malformado, obsoleto e omitido.
- Registro estrangeiro/fora da unidade deve ser negado antes da comparação.
- Falha não altera dados, vínculos ou trilha de sucesso; recarga exige acesso.
- Concorrência PostgreSQL: apenas a edição com revisão corrente pode persistir.
- Vue: rascunho, recarga, descarte de respostas de outra conta, nova confirmação.
- Chrome real, claro/escuro, 1440 e 390, persistência e navegação.
- Preservar todos os cenários e contratos já aprovados.

Implementação em preparação para validação nativa no próximo checkpoint; não homologada.
A recarga individual usa Cache-Control no-store. Uma regressão adicional cobre
o ciclo nativo de conta e a preservação de registros/histórico de outra conta.

## Escopo do checkpoint e testes preparados

- Base funcional de auditoria: 1877e145, CI 44101857764, 467 Rails, 197 Vue, 64 Chrome; hash do artefato 19ae152dd428f4cec48323dc2bd124a9f4b2aa8eecb1dafa7dd180d561454e23. Capturas e recibo verificados.
- Revisão visual identificou falta de herança de cor nos valores do popup escuro após Teleport. O componente de detalhes recebe cor explícita e o Chrome passa a comparar a cor calculada dos valores com o título autorizado em ambos os temas. Não alterar Dialog compartilhado.
- Tradução do código técnico provider para Regra do provedor nos detalhes/comparação.
- Revisão de unidades/filas/vínculos preserva clientes antigos, exige token válido no novo editor, mantém rascunho e bloqueia reenvio até recarga e confirmação. Editar após confirmar invalida a confirmação.
- Contexto capturado inclui conta, tipo e ID; respostas anteriores são descartadas. Nenhuma permissão é inferida pelo token.
- Preparados 26 novos exemplos Rails (incluindo escopo por unidade, ciclo de conta e uma corrida HTTP/PostgreSQL), 12 Vue e quatro cenários Chrome. Expectativa total: 493 Rails, 209 Vue e 68 Chrome; todos pendentes até a execução no novo SHA.
- Herança por equipe e elegibilidade de novos usuários permanecem abertas, sem concessões automáticas. A próxima etapa não equivale à conclusão integral 0–2 ou da Parte 1.

## Diagnóstico da primeira execução e preservação do ciclo de conta

CI 44108023316: 487 exemplos Rails, 485 aprovados e duas falhas,
zero pendências/erros fora dos exemplos. Artefato 14340335477,
SHA-256 0aefc9494b99eb31ed7e619fa4b6d66078fab42003d428dff222cae37bc3793e.
Vue/build/Chrome não foram aceitos nesse SHA.

A preparação de microssegundos usava Numeric#microsecond, ausente no runtime.
Passa a usar Rational(1, 1_000_000) na aritmética de Time, mantendo a exigência
de distinguir o estado com precisão de microssegundos.

O teste adicional de ciclo de conta assumia purga por Account.destroy!, sem
contrato existente que a autorize. O PostgreSQL mostrou FKs restritivas do
Call Center. Conferência da base a24adc6d e da candidata: schema blob idêntico
2da124014a50e68dca9ea4c4345ab9e377e2bddf, incluindo as 18 referências a accounts.
DeleteObjectJob nativo não prepara a purga de dependências Call Center.

Decisão de preservação: NÃO adicionar CASCADE, remover restrições ou inventar
retenção/purga. O cenário agora prova a rejeição nativa, rollback em savepoint,
persistência de conta/usuário/vínculo/unidade/fila/participante e imutabilidade
das trilhas própria e de outra conta. Não é homologação de exclusão completa.
Uma eventual política de exclusão/retenção de conta continua fora deste
incremento e precisa de decisão específica.

As correções de lint apenas removem linhas iniciais vazias, uniformizam hashes
dinâmicos e usam it_behaves_like, mantendo todos os exemplos e verificações.

## Revalidação da lógica nativa

CI 44112946513, cfcae689552c3c95e1e940f716cfd8506d7dabba:
487 exemplos Rails mais seis de concorrência, todos aprovados, com zero falhas,
pendências ou erros fora dos exemplos; 209 Vue aprovados. Artefato 14342351295,
SHA-256 a98ae71b5250974931ec782e6b94b490772d87b186f72e3e64937c8bc111377e.
Gate ainda bloqueado por uma única linha em branco extra no novo teste de
rollback. Correção exclusivamente de formatação, sem remoção/alteração de
asserções. Build/Chrome e contraste continuam pendentes no novo SHA.
