# Remoção do filtro visual de segmento — 16/11/2026

Estado: Aceita. Solicitação explícita do usuário: retirar “Filtrar por segmento” de todos os lugares e gerar uma nova imagem.

## Decisão e escopo

Partir do produto `5c3fb7f700d7bb685f17292f59b873df14ddf34d`, usado pela última imagem publicada. Remover o painel e o seletor compartilhados de CRM, Backoffice, Relacionamento, Projetos, Service Desk, Campanhas, Empresas e Contatos Operacionais. Remover os dois componentes sem consumidores e seus testes específicos; adaptar os testes de integração para exigir a ausência do controle e preservar os demais filtros.

Cadastros, classificações, permissões, dados persistidos, contratos de API e audiências de campanhas existentes continuam compatíveis. A remoção é da interface; não é uma migração ou exclusão de dados de segmentos. Nenhuma alteração funcional de Call Center foi incorporada.

## Aceite e evidências

- Nenhum consumidor Vue dos componentes removidos nem uso visual de `CRM.CORPORATE_SEGMENTS.FILTER_LABEL`/`SEARCH_FILTER` em `app` e `enterprise`.
- Compilação sintática dos 12 fontes alterados aprovada; 336 timestamps de migrations conferidos, zero migrations novas.
- ESLint dos arquivos alterados: zero erros, 35 avisos em código preservado.
- Vitest local não iniciou os testes porque a instalação compartilhada de dependências não contém `fake-indexeddb/auto/index.mjs`. A aprovação dos testes depende da CI com instalação pelo lockfile.
- Gerar e conferir uma imagem Linux/amd64 no SHA exato por `build-ghcr.yml`, incluindo seus gates e smokes existentes. Registrar SHA, execução e digest na entrega.

Publicação da nova imagem está no escopo solicitado. Implantação em ambientes existentes não foi solicitada.
