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
