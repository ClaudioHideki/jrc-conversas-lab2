# Evidencias de verificacao

Data: 02/10/2026. Originais conferidos por SHA-256 e CRC antes da extracao. O fechamento da entrega inclui nova conferencia dos hashes dos originais, CRC do ZIP final e hashes de cada arquivo arquivado.

## Executado com sucesso

- 387 testes Node: 353 casos oficiais Service Desk, 10 casos novos de payload/empresa e 24 casos oficiais de Projetos/Agenda/CRM UI. Sao helpers/contratos isolados, nao browser/Vue compilado.
- 38 testes Ruby novos/portados do mestre: 28 de identidade/documentos e 10 de decisao de vinculo, 93 assertions no total.
- 105 testes Ruby em outras suites oficiais verdes, 6.837 assertions: clock engine, configuration, history projection, lifecycle migration/modelo puro, comissoes, financeiro e metas.
- Total das suites Ruby verdes: 143 testes / 6.930 assertions. Isso NAO inclui como aprovadas as suites vermelhas abaixo.
- 87 arquivos Ruby/rake/Jbuilder passaram em `ruby -c`.
- 39 scripts JS (incluindo os script blocks das SFC) foram analisados sintaticamente com Acorn disponivel no ambiente.
- 28 templates Vue passaram na verificacao estrutural de tags; 240 imports locais revisados resolveram para arquivos existentes.
- 220 migrations historicas, schema.rb, lockfiles e arquivos Docker protegidos permanecem identicos. 17 arquivos de nucleo/configuracao SIP/WebRTC tambem permanecem identicos.

## Falhas preexistentes reproduzidas

Os testes e componentes correspondentes foram executados tambem na pasta OFICIAL intacta e retornaram os mesmos sintomas e totais:

| Suite oficial | Resultado na oficial e no candidato |
|---|---|
| `jrc_service_desk_capabilities_test.rb` | 11 casos / 825 assertions; 1 falha: expectativa de 33 capacidades versus 37 atuais. |
| `jrc_service_desk_policy_scope_test.rb` | 6 casos / 34 assertions; 3 erros: fixture `ScopeFixtureContext` sem `view_unit_scope`. |
| `jrc_service_desk_structure_contract_test.rb` | 11 casos / 136 assertions; 1 falha na expectativa de papeis nativos sem acesso estrutural. |

Essas suites nao foram alteradas para encobrir o resultado. A reproducao demonstra que os sintomas precedem o Cadastro Mestre, nao certifica a seguranca ou intencao das regras de permissao. Devem ser investigadas no laboratorio.
Logs integrais, incluindo os da oficial, estao na pasta `evidencias/`. Seeds e tempos podem variar; compare as mensagens/assertions, nao somente o texto bruto dos logs.

## Nao executado / nao homologado

72 blocos `it` de RSpec do Cadastro Mestre estao escritos (50 recuperados da referencia e 22 novos de operacoes/comercial/backfill/merge), mas NAO executados com Rails/PostgreSQL.
O teste de inicializacao Bundler falhou de forma objetiva: Ruby local 3.3.8, Gemfile exige 3.4.4. O Gemfile nao foi alterado para contornar isso.
O compilador Vue nao estava instalado. Tentativa isolada/offline de obter a versao bloqueada nao encontrou cache; a tentativa de rede falhou em DNS (`EAI_AGAIN`). Nao houve alteracao de package.json/lockfiles do projeto.
Portanto: Rails boot, migrations, PostgreSQL, constraints reais, backfill real, RSpec, build Vue/Vite, lint completo, HTTP, navegador, performance, Docker e integracoes externas/PABX continuam pendentes.
As verificacoes de sintaxe/estrutura nao substituem compilacao e testes funcionais.

## Reproduzir testes isolados

Na raiz do projeto, sem modificar dependencias:

```sh
ruby test/jrc_customers/identity_pure_test.rb
ruby test/jrc_customers/company_link_decision_test.rb
node --test test/jrc_customers/*.test.mjs test/jrc_operations/*test.mjs test/jrc_consolidation/commercial_ui.test.mjs
```

As suites oficiais Ruby podem ser executadas uma a uma em `spec/isolated/*_test.rb` e `test/jrc_consolidation/*_test.rb`; execute cada arquivo em processo separado. As tres falhas acima continuam presentes.
O ambiente alvo deve usar as versoes/dependencias declaradas pelo projeto. Este pacote e candidato, nao uma versao homologada para producao.
