# JRC CRM - Estrutura Organizacional configuravel

Data: 02/10/2026

## Objetivo

Evoluir a configuracao geral do CRM sem criar cadastros paralelos e sem codificar nomes especificos do Grupo JRC.

Modelo adotado:

```text
Account / Tenant
  -> Grupo / Organizacao (rotulo configuravel)
     -> Empresas internas (Cadastro Mestre / companies, relacionamento=internal)
        -> Unidades de negocio (jrc_crm_business_units)
     -> Departamentos / Equipes (Team nativo)
        -> Abrangencia do departamento: Grupo, Empresa ou Unidade
        -> Abrangencia individual do colaborador: Grupo, Empresa ou Unidade
```

O mesmo desenho atende uma empresa unica, um grupo com varias empresas, filiais/unidades, departamentos locais e departamentos corporativos compartilhados.

## Decisoes implementadas

1. Nao foi criada tabela paralela de empresa do CRM. Empresas operacionais usam a Empresa Mestre existente (`companies`) com `relationship_type=internal`.
2. `JrcCrm::BusinessUnit` foi evoluida para poder pertencer a uma Empresa Mestre interna. Registros antigos continuam validos com `company_id` nulo e sao marcados na interface como legado sem empresa.
3. Departamentos/equipes reutilizam `Team` e `TeamMember` nativos do JRC Conversas.
4. Foi criada `JrcCrm::TeamScope` para declarar onde um departamento pode atuar: Grupo, Empresa ou Unidade.
5. `JrcCrm::UserBusinessUnit` foi preservada e evoluida para guardar a abrangencia individual configurada. Registros legados nao sao convertidos automaticamente (`structure_managed=false`).
6. Quando um colaborador recebe um escopo dentro de uma equipe, o backend valida que ele e membro da equipe e que o escopo individual nao ultrapassa o escopo do departamento.
7. Abrangencia e permissao funcional permanecem separadas. Os novos escopos nao armazenam novas permissoes de acao; papeis e Custom Roles continuam sendo a fonte das permissoes funcionais.
8. A aplicacao dos limites organizacionais na visibilidade do CRM e opt-in. Quando ativada, `OrganizationalVisibility` apenas restringe a relacao que o CRM ja permitiria pelo comportamento legado. Ela nunca amplia acesso, nunca concede registros de outro responsavel e nao altera o bypass nativo de administrador.
9. Usuarios sem escopo organizacional configurado continuam com o comportamento legado, mesmo quando a aplicacao dos limites estiver habilitada. Isso evita bloqueio acidental durante a transicao.

## Interface

Em `CRM -> Configuracoes` foi adicionada a aba `Estrutura Organizacional`, contendo:

- nome do Grupo/organizacao;
- ativacao opt-in da restricao organizacional;
- empresas internas;
- unidades de negocio;
- departamentos/equipes nativos;
- membros das equipes;
- abrangencia do departamento;
- abrangencia individual por colaborador.

Exemplo do Grupo JRC suportado sem hardcode:

```text
Grupo JRC
  GoPure
    Unidade A
    Unidade B
  Operadora
    Unidade A
  Construtora
  Financeiro do Grupo -> escopo Grupo
  Backoffice do Grupo -> escopo Grupo
  Suporte do Grupo -> escopo Grupo
```

Um colaborador do Financeiro pode, por exemplo, receber somente `GoPure`, enquanto outro pode receber uma unidade da Operadora. O departamento continua corporativo, mas a abrangencia individual pode ser menor.

## Compatibilidade e seguranca

- Nenhuma migration historica foi alterada.
- `db/schema.rb` nao foi alterado manualmente.
- Nenhum lockfile foi alterado.
- Nenhuma configuracao SIP/WebRTC/PABX foi alterada.
- Nenhum nome GoPure/Operadora/Construtora foi gravado como regra de codigo.
- Nenhuma correspondencia automatica foi feita entre unidades antigas e empresas.
- A nova migration e aditiva e o `down` e intencionalmente irreversivel para evitar perda de atribuicoes revisadas.

## Limites desta rodada

A configuracao da estrutura organizacional esta implementada, mas esta rodada nao substitui as proximas configuracoes gerais do CRM, como:

- matriz completa de perfis e permissoes de gestor/vendedor/Financeiro/Backoffice/Suporte;
- regras de compartilhamento de carteira, produtos, funis e dados financeiros;
- metas e comissoes por nova hierarquia;
- aprovacoes e alcadas;
- automacoes baseadas na hierarquia.

A restricao organizacional atual e deliberadamente conservadora: ela reduz a visibilidade permitida pelo fluxo legado, mas nao concede acesso transversal a registros de outros responsaveis. A concessao transversal deve ser definida na fase de Permissoes para nao misturar alcance organizacional com privilegio funcional.
