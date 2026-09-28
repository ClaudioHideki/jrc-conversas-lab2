# Estado atual - CP2 apos aprovacao humana

CP2-D01/CP2-D02: APROVADAS, opcao A. Fundacao implementada para revisao.
Consulte `CP2_IMPLEMENTACAO.md` para o resultado atual e `CP2_MODELO_DE_DADOS.md` para as
fichas executaveis. Specs escritos nao equivalem a execucao nativa.
**PENDENTE — validação nativa em ambiente Docker/local**.
Nenhum CP3 iniciado. Nenhuma CP2-D03+ pendente nesta rodada.

## Historico preservado da preparacao (nao e o estado atual da implementacao)

> Atualizacao de continuidade: CP2-D01 e CP2-D02 foram APROVADAS, opcao A.
> O conteudo abaixo preserva a preparacao anterior. O desenho executavel, resultados e
> testes atuais sao registrados em CP2_MODELO_DE_DADOS.md e CP2_IMPLEMENTACAO.md.
> SD-D01 a SD-D05 permanecem obrigatorias. Somente CP2 autorizado.

# CP2 - matriz de testes a implementar depois das decisoes

**PLANO, NAO SPECS EXECUTAVEIS. NENHUM TESTE OPERACIONAL CP2 EXECUTADO.**
CP2-D01/D02 bloqueiam a especificacao final dos fixtures de unidade e das concessoes.
Nao criar um teste positivo que aprove permissoes ainda nao decididas.

## Reuso dos padroes existentes

A baseline usa `require 'rails_helper'`, RSpec, FactoryBot/factories nativas e testes com
registros de Account independentes. `spec/models/jrc_crm/deal_spec.rb` ja cria contato de
outra conta para exigir validacao negativa; o CP2 deve cobrir tambem SQL/constraints,
services e scopes, em vez de confiar somente na validacao do model.

## Matriz minima futura

| ID | Nivel | Cenario e resultado exigido | Estado |
|---|---|---|---|
| CP2-T01 | Models | Validar titulo/referencias obrigatorias, valores configurados e estado ativo. | A implementar; bloqueio arquitetural. |
| CP2-T02 | Relacoes | Carregar entidades reais de duas Accounts e negar todos os vinculos cruzados. | A implementar; bloqueio arquitetural. |
| CP2-T03 | Unidade | Negar outra unidade da mesma Account conforme decisao aprovada, inclusive por ID direto. | A implementar; CP2-D01/D02. |
| CP2-T04 | Policy | Agente/admin/papel customizado sem acao ou sem escopo nao recebe registros. | A implementar; CP2-D02. |
| CP2-T05 | Scope | Lista e busca por ID usam o mesmo escopo; nenhum fallback ao model global. | A implementar; CP2-D02. |
| CP2-T06 | Feature | Flag desligada nega comandos/leituras; outras flags e bits nao mudam. | A implementar para CP2; specs CP1 preservados. |
| CP2-T07 | Services | Account/ator vem do contexto nativo; params nao trocam a Account, autor ou escopo. | A implementar depois do contrato de comando. |
| CP2-T08 | SQL | INSERT/UPDATE direto que ignora validacoes nao permite FK de outra Account nas relacoes protegidas. | A implementar com constraints fechadas. |
| CP2-T09 | Concorrencia | Duas mutacoes concorrentes nao apagam historico nem sobrescrevem versao silenciosamente. | A implementar com transacoes/lock_version. |
| CP2-T10 | Auditoria | Mutacao relevante + evento atomicos; falha no evento nao apresenta sucesso sem evidencia. | A implementar com dominio de historico. |
| CP2-T11 | Snapshot | Nova versao nao modifica a aplicada; sem contrato/calculo nao existe cobertura/prazo ficticio. | A implementar sem provedor externo. |
| CP2-T12 | Anexos/notas | Negar blob de registro nao autorizado e leitura de nota interna; nao copiar Message. | A implementar no dominio autorizado de anexos. |
| CP2-T13 | Migrations | Up/down/up numa copia isolada; nenhuma mudanca de schema nativo fora do diff aprovado. | A implementar; nenhuma migration criada. |
| CP2-T14 | AccountUser | Revogacao de vinculo nativo nao deixa comando antigo reaproveitar contexto valido indevidamente. | A implementar com escopo aprovado. |
| CP2-T15 | Integridade | Solicitante, responsavel, Team, fila e classificacao da Account/unidade correta. | A implementar apos modelagem. |
| CP2-T16 | Regressoes | Preservar Conversas/CRM/Campanhas/NICO/Calling/Cockpit/flags e suites CP1. | PENDENTE — validação nativa em ambiente Docker/local. |

## CP1 continua pendente

**PENDENTE — validação nativa em ambiente Docker/local**:
- carregamento Rails/ActiveRecord e `zeitwerk:check`;
- cinco arquivos RSpec do CP1 e `spec/models/concerns/featurable_spec.rb`;
- `app/javascript/dashboard/__tests__/serviceDeskFeatureFlag.spec.js` com Vitest;
- autenticacao/HTTP/feature desligada e smoke do JRC no runtime requerido.

Esses arquivos nao foram removidos nem alterados. Nenhum Rails/RSpec/Vitest foi declarado
aprovado. O fato de a baseline ter hash correto nao demonstra o funcionamento da aplicacao.

## Ambiente

Ruby 3.4.4, Node 24.13.0, Bundler 2.5.16, pnpm 10.2.0, gems/pacotes dos lockfiles e banco/Redis
isolados de teste. Nao usar dados reais, alterar runtimes declarados, apagar banco ou adaptar
configuracoes existentes apenas para contornar um erro. A geracao de schema, quando houver
migrations aprovadas, sera pelo Rails; nunca editar `db/schema.rb` manualmente.

## Validacoes desta rodada

Somente as verificacoes documentais/estaticas descritas no manifesto e nos logs externos
foram executadas. A lista acima e um plano de cobertura, nao uma estatistica de testes verdes.
