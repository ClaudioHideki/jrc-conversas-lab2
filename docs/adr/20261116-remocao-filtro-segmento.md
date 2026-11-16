# Remoção do filtro visual de segmento — 16/11/2026

Estado: Aceita. Solicitação explícita do usuário: retirar “Filtrar por segmento” de todos os lugares e gerar uma nova imagem.

## Decisão e escopo

Partir do produto `5c3fb7f700d7bb685f17292f59b873df14ddf34d`, usado pela última imagem publicada. Remover o painel e o seletor compartilhados de CRM, Backoffice, Relacionamento, Projetos, Service Desk, Campanhas, Empresas e Contatos Operacionais. Remover os dois componentes sem consumidores e seus testes específicos; adaptar os testes de integração para exigir a ausência do controle e preservar os demais filtros.

Cadastros, classificações, permissões, dados persistidos, contratos de API e audiências de campanhas existentes continuam compatíveis. A remoção é da interface; não é uma migração ou exclusão de dados de segmentos. Nenhuma alteração funcional de Call Center foi incorporada.

## Aceite e evidências

- Nenhum consumidor Vue dos componentes removidos nem uso visual de `CRM.CORPORATE_SEGMENTS.FILTER_LABEL`/`SEARCH_FILTER` em `app` e `enterprise`.
- Compilação sintática dos 12 fontes alterados aprovada; 336 timestamps de migrations conferidos, zero migrations novas.
- ESLint dos arquivos alterados: zero erros, 35 avisos em código preservado.
- Vitest local não fornece aprovação: o resolvedor não carregou uma dependência compartilhada e a tentativa com leitura explicitamente permitida terminou por falta de memória. A aprovação dos testes depende da CI com instalação pelo lockfile.
- Gerar e conferir uma imagem Linux/amd64 no SHA exato por `build-ghcr.yml`, incluindo seus gates e smokes existentes. Registrar SHA, execução e digest na entrega.

A primeira execução `43937497762` aprovou os dois jobs de regressão, mas o gate Ruby puro terminou com 11 erros de carregamento de `JrcRelationship::PrioritySignals`. Esse teste executa sem o autoload do Rails e não carregava `PrioritySignals`/`PriorityBands`, já usados pelo serviço preservado. Foram acrescentados somente os dois `require_relative` no teste existente; expectativas e fontes funcionais Ruby permanecem intactas. Repetir todos os gates no commit corrigido.

Após a correção, o comando exato de testes puros de Relacionamento e Operações passou na imagem Ruby existente, sem rede e com o código montado somente para leitura: 92 testes, 483 assertions, zero falhas, erros ou skips.

A execução `43938866546` aprovou os jobs iniciais, incluindo 168 exemplos Rails, e todos os gates puros. A suíte Vue passou 2.751 de 2.752 testes em 295 arquivos; a única falha era uma expectativa remanescente de exibir/acionar o seletor removido em `useCompanyDirectory.spec.js`. Esse cenário foi adaptado para exigir a ausência do seletor e de chamadas ao catálogo, mantendo a compatibilidade dos parâmetros recebidos e os outros filtros. Não houve outra mudança funcional.

Publicação da nova imagem está no escopo solicitado. Implantação em ambientes existentes não foi solicitada.

## Resultado verificado — 16/11/2026

- Produto: `c8efa1d68e1b5706e47cd022fa8e31df1e156e6c`.
- Tag: `ghcr.io/claudiohideki/jrc-conversas-lab2:sha-c8efa1d68e1b5706e47cd022fa8e31df1e156e6c`.
- Referência exata: `ghcr.io/claudiohideki/jrc-conversas-lab2@sha256:010c0d5ce22f467f06d4d81fddcebca3a27860ac77ca5bfc95c947436a1d55fa`.
- [Execução 43941168985](https://github.com/ClaudioHideki/jrc-conversas-lab2/actions/runs/43941168985): os três jobs terminaram com sucesso no SHA do produto.
- Frontend: 295 arquivos e 2.752 testes aprovados. Regressões Rails: 168 exemplos sem falhas. Relacionamento/Operações puros: 92 testes, 483 assertions, zero falhas, erros ou skips.
- Gates de sintaxe, integridade e lint aprovados. Nove migrations e 17 arquivos de produto conferidos dentro do artefato; manifestos e entradas de assets compilados presentes.
- Linux/amd64, label de revisão e `/app/.git_sha` conferidos. Rails/Sidekiq e transporte sintético testados antes do push e novamente na imagem publicada por digest.
- O digest foi consultado independentemente pelo Docker do desktop, sem baixar as camadas novas no disco local.

Não foram alterados migrations, dependências, Dockerfile, dados, permissões ou fontes funcionais Ruby. A branch de entrega permanece separada; nenhuma implantação foi executada. Este registro posterior documenta o produto identificado acima e não substitui seu SHA de origem.
