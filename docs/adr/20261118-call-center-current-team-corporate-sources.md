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
  redundante na fonte. O modelo nativo proíbe substituir uma empresa já
  estabelecida da unidade; essa proteção permanece inalterada.
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
  preservação da imutabilidade nativa da empresa da unidade.
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


## Correção da preparação e caminhos após 6c728416

CI 44250259196: 845 exemplos Rails principais, uma falha, zero pendências
ou erros externos; 16 do ledger após recarga aprovados. Artefato 14403833585,
SHA-256 a993987a9271d2ee83c68a116ba6489da10187b03e91960c1a43809b0a2790e7.
A preparação do novo cenário tentou trocar uma empresa que BusinessUnit
já preserva por validação. O cenário agora exige essa rejeição e a manutenção
da cobertura válida; não alterar o modelo nem permitir a transferência.

Os dois apontamentos de lint exigem caminhos correspondentes às classes:
team_corporate_scope_spec.rb passa a spec/services/jrc_crm/current_structure_scopes_spec.rb;
call_observation_authority_spec.rb passa a call_observation_writer_authority_spec.rb
no mesmo domínio CC. Os mesmos exemplos são preservados uma única vez.
O workflow inclui explicitamente o novo caminho CRM. O auxiliar de checkpoint
só admite essas duas renomeações de testes criados nesta tarefa, verifica os
hashes históricos, recusa destinos existentes e exige as duas metades juntas.
Oito testes puros do auxiliar foram aprovados; não são testes Rails.
A remoção do caminho antigo na árvore segue o [contrato da API Git Trees](https://docs.github.com/en/rest/git/trees#create-a-tree),
com base_tree preservado; isso não autoriza remoções genéricas ou limpeza.

Nova validação nativa obrigatória. A atividade recente da Central é outro
incremento ainda em preparação e não integra este checkpoint corretivo.


## Coordenação das escritas de configuração — 6ab822a0

CI 44253568507: 845/845 Rails principais e lint sem novas infrações;
22/23 concorrentes e 16/16 reexecuções do ledger no schema recarregado.
Artefato 14406300059; SHA-256
abf28821f6246e1fe97527541768b5913b61625142846bff5b1902a1f082a16d.

O cenário da fila não encontrou espera em Account. A inspeção confirmou que
ConfigurationWrite só abria transação/locks do registro e seus pais. Para
coordenar essas escritas com revogações corporativas e de perfil, create! e
update! usam agora Account.with_lock como transação externa, mantendo a
mesma ordem Account → registro/fila → unidades, os checks e a revisão
existentes. FactsProjector e EventReconciler já usam Account antes da chamada.
Não remover o teste de espera, aumentar timeout ou aceitar resposta incerta.
O diagnóstico de timeout passa a registrar somente status HTTP observado e
o lock esperado; nenhum header, payload ou credencial. Resultado da nova
execução pendente, incluindo regressões corporativas, Vue e 112 Chrome.


## Resultado nativo de 03de3a8f e regressões corporativas

CI 44255888203: 845/845 principais, 23/23 concorrentes e 16/16
reexecuções do ledger aprovadas. O cenário da fila comprovou espera real em
Account e negou a gravação após revogação da fonte; nenhuma auditoria de
atualização foi criada. Zero novas infrações Ruby em 155 arquivos comparados.
Artefato 14407681498, SHA-256
41e7e059d1b26c17685b05cebb0637efe03eca4e1c33b55ac8645d1212a084cf.

A suíte adicional executou 84 exemplos e teve duas falhas, sem pendências
nem erros externos. A extração do PDF devolveu texto vazio, e o workflow
não declarava Poppler, exigido pelo TextExtraction nativo. Declarar
poppler-utils pelo mesmo helper HTTPS/assinaturas e verificar o executável
antes dos testes. Exigir também engine poppler e manter todas as provas de
nomes, identificadores sintéticos, âncoras únicas e hash do PDF. Essa
correção de ambiente ainda precisa demonstrar o resultado no novo SHA.

O INSERT do outro cenário tornava duas FKs inválidas simultaneamente. O
PostgreSQL rejeitou pela origem da solicitação, mas o teste exigia a do
contrato. Separar os dois cenários com origens estrangeiras criadas pelos
serviços/fixtures nativos: só uma FK composta inválida em cada tentativa,
exigindo seu nome exato e a preservação do registro e do escopo original.
Não aceitar um erro genérico, remover constraints ou alterar migrations.
São 85 exemplos corporativos esperados após essa ampliação. Nenhum código
funcional do Backoffice ou do gerador de PDF foi alterado.

Vue e Chrome não rodaram nesse SHA. A atividade recente continua em
incremento separado, sem alegar aceite integral das figuras do Word.


## Aceite incremental de ac85d6eb

CI 44260446025 aprovada: 845 principais + 23 concorrentes + 85 corporativos,
953 exemplos Rails únicos. As 16 provas do ledger foram reexecutadas em
outro banco de recarga e não são contadas como casos novos. 300 Vue e
112 Chrome aprovados, sem falhas/pendências/skips/flaky/erros externos;
bootstrap real com 15 cards, migrations/SQL, lints e assets aprovados.
Artefato 14410325587; SHA-256
05357d9e829154191bce2b8c335513f1512c4e2795767ab45acfcdb93c898ca0.
Os hashes das 144 capturas foram conferidos contra o artefato. Isso não
significa revisão visual individual de todas as capturas.

Poppler real extraiu nomes/identificadores sintéticos e todas as âncoras;
os dois cenários independentes provaram as FKs por nome exato, mantendo
o registro original. Não houve alteração no gerador, migrations ou FKs.
As provas de remoção/reinclusão por equipe também passaram nos quatro
projetos Chrome. A configuração completa da equipe/supervisão/hierarquia
e as dependências de negócio/fornecedor permanecem pendentes do Word.
A atividade recente e a descoberta do editor local são um próximo incremento,
ainda sem usar estas evidências como se fossem seus testes.
