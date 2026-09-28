# CP6-D01 - APROVADA

A aprovacao humana substitui o estado pendente abaixo. Implementacao e limites em
`CP6_D01_APROVADA.md`. Nenhuma nova decisao pendente nesta continuacao.

## Historico integral anterior (nao vigente)

# CP6-D01 - DECISAO PENDENTE: administracao da estrutura e concessao inicial

Registro: 28/09/2026. As decisoes SD-D01..SD-D05, CP2-D01/D02 e CP4-D01 permanecem aprovadas.

## Problema
CP2-D02 exige UnitMembership ativo ate para administradores e nao admite autoconcessao.
O CP5 tem capacidades para catalogos, mas nao para criar operadoras/unidades ou conceder
UnitMembership. Uma unidade nova ainda nao possui membership. Criar um bypass de Account
ou usar settings_view como poder de conceder unidades reinterpretaria os contratos.

## Alternativas e impactos
A. Administracao estrutural explicita fora do acesso operacional, restrita a um ator nativo
   autorizado, com capacidades dedicadas e auditoria; acesso a chamados ainda requer
   membership independente. Exige definir autoridade, aprovacao e revogacao antes de codificar.
B. Procedimento assistido fora da interface, mediante autorizacao humana nominativa no
   ambiente de teste. Nao cria delegacao online, mas aumenta trabalho e depende de evidencias.
C. Delegacao por operadora, com vinculos administrativos proprios e capacidades nativas.
   Nao equivale a acesso operacional, mas introduz estrutura adicional e exige aprovacao.

Recomendacao tecnica: A, sem implementa-la nesta rodada. A criacao/edicao/ativacao da
estrutura e o gerenciamento de memberships continuam PENDENTE FUNCIONAL. Nao criar uma
unidade default, atribuir a unidade ao criador automaticamente nem emprestar permissoes.

Somente esta parte para. CRUD de filas, categorias, prioridades, status, servicos e a
publicacao versionada de politica ja possuem capacidades/regras aprovadas e podem continuar.
O roteiro de homologacao exige estrutura de teste previamente provisionada por procedimento
explicitamente autorizado, ou aguarda a decisao A. Nao contem autoconcessao oculta.
