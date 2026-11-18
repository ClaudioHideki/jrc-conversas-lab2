# Cobertura corporativa atual das equipes nativas

Estado: 77be76ae executado com falhas; correções e ampliação preparadas,
validação nativa do próximo SHA pendente. Escopo autorizado:
continuidade do Call Center e prevenção de reativação indevida de permissões.

## Problema comprovado no código

`JrcCrm::TeamScope` e `UserBusinessUnit` já são os registros nativos de
cobertura. O vínculo opcional com equipe é validado ao salvar o registro do
usuário. Antes deste incremento, `CorporateCoverage#scopes` não repetia essa
conferência ao consultar uma fonte ativa. Remover o membro ou reduzir/desativar
o escopo da equipe podia deixar a cobertura anterior efetiva. Não há motivo
para criar outro cadastro de equipes, usuários ou abrangências.

## Decisão

- A consulta exige associação atual com equipe da mesma conta e um TeamScope
  ativo que contenha integralmente a fonte explícita do usuário. GROUP exige
  GROUP; COMPANY pode estar dentro de GROUP ou da mesma COMPANY;
  BUSINESS_UNIT pode estar dentro desses dois ou da mesma BUSINESS_UNIT.
- A consulta continua relacional no PostgreSQL, sem materializar um conjunto
  de IDs por usuário. Os predicados de conta e equipe não ficam fora dos
  parênteses da disjunção de escopos.
- Fontes diretas sem equipe são preservadas. Não são criadas, desativadas,
  copiadas nem reativadas fontes ou permissões. Presença online, cargo e nome
  de equipe continuam sem conceder elegibilidade ou distribuição em filas.
- Uma fonte de unidade usa a empresa atual da unidade para verificar a
  cobertura por COMPANY da equipe. Não confiar em company_id redundante
  que ficou guardado na fonte depois de uma transferência da unidade.
- Reincluir um usuário com fonte corporativa de equipe ainda marcada ativa
  exige a autoridade nativa de administrador com cobertura GROUP, inclusive se não há
  unidades configuradas; uma fonte GROUP guardada não é bootstrap implícito. A guarda também vale com o
  módulo CC desabilitado; a fonte corporativa pertence ao produto principal.
  Uma fonte explicitamente inativa não é ativada por inclusão na equipe.
- Remover membros e remover IDs ausentes não são adições. Na substituição
  completa, uma adição negada não pode remover os membros anteriores.
- As seis mutações nativas de escopos de usuário/equipe e as mutações de
  membership usam o lock da conta. Revalidam o ator, suas permissões nativas
  e a autoridade corporativa depois da espera, com cache de consulta desativado.
  O lock de membership também é obtido na ausência de fontes atuais para não
  abrir uma corrida com a primeira configuração corporativa.
- A autorização de consulta continua independente das capacidades funcionais
  do CC. Não é introduzido bypass por administrator ou SuperAdmin.

## Impacto e limites

O consumidor compartilhado atende CRM, Backoffice e Call Center. A autorização
de Aprovações possuía outro seletor direto de UserBusinessUnit e passa a
reutilizar a mesma relação de fontes atuais, preservando suas capacidades.
O leitor de bindings da Operadora tinha o mesmo seletor direto e recebe a
mesma substituição de uma linha, com regressão de leitura e dos comandos
nativos já existentes (fornecedor simulado nesses testes). Não são alterados
contratos externos, comandos ou credenciais. O link de Aprovações da Central
também consulta somente fontes atuais. A retirada da equipe remove a fila
da consulta de memberships operacionais, sem apagar o vínculo guardado.
Por isso a CI inclui as regressões nativas de CorporateCoverage, estrutura
organizacional, autorização de empresas e motor de Aprovações, além dos
testes existentes do CC e de equipes/agentes. Não há migration, alteração de
SQL histórico, concessão real ou mudança na configuração de clientes.

Não muda a semântica nativa de `configured?` nem o bootstrap de contas sem
estrutura. A política de retirada da última unidade corporativa não é
inventada neste incremento. As FKs existentes que impedem excluir equipe
referenciada são preservadas. Supervisor principal, status de equipe e
hierarquia equipe/fila continuam lacunas separadas das figuras 3 e 12.

## Critérios de validação preparados

- Dezessete exemplos de fontes atuais: retirada, escopo reduzido/inativo,
  GROUP herdado, unidade válida, fonte direta independente, outra equipe e
  outra conta, fonte explícita inativa, reinclusão sem escopo válido,
  Backoffice, decisão e link de Aprovações, Operadora, memberships e
  transferência da unidade para fora da empresa coberta pela equipe.
- Treze exemplos de membership autenticado: POST/PATCH com CC ligado/desligado,
  autoridade GROUP, retirada/no-op, atomicidade da substituição, fonte inativa
  e conta externa.
- Cinco exemplos das APIs nativas de escopos, incluindo os seis verbos de
  criação/edição/exclusão, perda de GROUP e permissão administrativa.
- Três corridas HTTP reais: reinclusão após revogação de GROUP, alteração
  de escopo após revogação e escrita CC após perda do escopo herdado. Cada
  corrida exige `pg_stat_activity` comprovando espera no lock de Account.
- Os quatro cenários Chrome de cobertura recebem retirada e reinclusão pela
  API nativa, ocultação na interface, acesso forçado negado e recuperação
  somente pelo administrador GROUP. Mantidos os 112 cenários, todos os passos
  anteriores e a execução em desktop/celular, claro/escuro.

Os dados e concessões de teste são sintéticos, exclusivos do runner e nunca
configuração operacional. Os resultados desta preparação ainda dependem da
execução no novo SHA; a CI de 417bb868 não contém esta correção.

## Resultado e correções de 77be76ae

CI 44246410692: 820 exemplos Rails principais, sete falhas, zero pendências
ou erros fora dos exemplos; 16 exemplos do ledger no schema recarregado
aprovados. Concorrência, regressões corporativas adicionais, Vue e Chrome
não foram concluídos nesse SHA. Artefato 14402447954; SHA-256
2149b13c54c4e8bf96408d1618f37cce59491512681c14ab49a533a1daab60f2.

As sete falhas ocorreram depois das respostas HTTP esperadas e usavam
`team.team_members.empty?` depois de mutações de preparo que conservaram a
associação em memória. Exigir consultas novas a TeamMember no banco para
provar a remoção, sem retirar as exigências de 401/200, preservação da fonte
e ausência de aumento de acesso. Os onze apontamentos novos de RuboCop
foram tratados sem exclusões: callback registrado no concern para manter
o controller dentro do limite, quatorze fixtures por grupo, enumeração fora
do loop, classe descrita explicitamente e argumentos nomeados alinhados.

O próximo gate inclui as ampliações acima e a reautorização da escrita de
observações documentada no ADR próprio. São 47 novos exemplos preparados
desde 417bb868, sem contar novamente as suítes nativas de regressão já
existentes. Ainda não são resultados aprovados.
