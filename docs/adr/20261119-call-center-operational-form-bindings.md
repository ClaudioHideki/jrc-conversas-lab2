# Formulários operacionais do ACW sem alterar o legado

Status: implementado para validação nativa; não homologado nem ativado em produção.

## Decisão

A figura 9 exige formulários reutilizáveis, versionados e com obrigatoriedade real no pós-atendimento. Reutilizamos a biblioteca e o motor de campos existentes. O vínculo é uma configuração atômica da regra nativa, com versão exata, hash e união dos campos obrigatórios. A precedência aprovada fila → equipe → geral escolhe a regra inteira; o formulário não herda de um nível inferior se a regra vencedora não tiver vínculo.

Cada novo ACW vinculado captura somente referências imutáveis, a origem nativa e a unidade/fila históricas em um estado privado subordinado à qualificação existente. A fila atendida do snapshot tem precedência; se indisponível, utiliza-se a origem corrente do atendimento no instante de captura, sem afirmar que ela prova a unidade atendida anterior. Não há outro cadastro nem outra qualificação. Os atendimentos antigos sem esse estado permanecem exatamente no contrato anterior. As cinco opções antigas de motivo e os códigos das regras capturadas são congelados somente nesse novo estado; isso não substitui o catálogo de classificações ainda pendente.

Rascunho e conclusão usam os locks, revisão, auditoria e APIs nativas. Respostas aceitam tipos, inclusive false e zero. A conclusão exige os campos obrigatórios da versão original; nenhuma expiração ou gravação de rascunho conclui o ACW. A pausa diferida permanece bloqueada até a conclusão explícita de todos os ACWs e o fim da chamada. Uma versão nova afeta apenas atendimentos futuros.

## Autoridade e preservação

O catálogo continua exclusivo da configuração autorizada. A definição operacional e as respostas são entregues somente ao proprietário autorizado da qualificação. Cada leitura/gravação revalida o acesso nativo e o escopo original, além da origem atual do atendimento. Transferir a chamada não concede acesso às respostas de outra unidade. Outros atores recebem somente o payload legado e não a assinatura privada. A assinatura privada usa HMAC e não permite inferir respostas em logs de auditoria. Parâmetros de respostas e inspeção do model são filtrados. Não se registram respostas completas em logs.

A migration 20261119203000 é uma quinta adição isolada e fixa por hash; as quatro anteriores, o schema histórico e SQLs não mudam. PostgreSQL valida conta, versão, evento ACW de origem, imutabilidade e selagem após conclusão. A recarga do schema reutiliza o dumper nativo. A reexecução verifica o recibo estrutural e não recria silenciosamente um esquema adulterado. O bloqueio nativo de retirada da conta com histórico permanece preservado.

## Evidências exigidas

Testes nativos autenticados de persistência, obrigatoriedade, legado, troca de unidade, negação de acesso e concorrência com conexões PostgreSQL distintas; instalação/recarga/reexecução e adulteração de triggers; testes Vue dos seletores e respostas tardias; dois novos cenários Chrome em quatro projetos (192 no total, mantendo os 184 anteriores). Apenas testes locais estáticos foram executados durante a preparação; resultados nativos serão registrados no checkpoint correspondente.

Permanece pendente a homologação externa do PABX e o aceite integral das 23 figuras, incluindo histórico operacional detalhado e automações. Nenhum comando externo ou alteração em produção é autorizado por esta decisão.
