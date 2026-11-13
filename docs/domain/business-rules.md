<!-- jrc-operational-init:v1 -->
# Regras de negócio — JRC Conversas LAB2 — Grupo JRC

Estas regras documentam o escopo conhecido e preservam as decisões específicas anteriores; não ativam comportamentos no produto.

- Aplicar visibilidade por Account, caixa, membership, atribuição, exclusividade e supervisão.
- Preservar importação histórica silenciosa: não disparar bots, pesquisas ou reatribuição por importar história.
- Manter entrada/saída e mídias identificadas pelo canal correto.
- Não promover extensões GLPI específicas da Branef para o núcleo genérico.

## Regras de manutenção

- Preservar as regras específicas preexistentes do projeto e os trabalhos concorrentes.
- Separar código implementado, teste local, CI, imagem publicada, implantação e aceite operacional.
- Registrar decisões relevantes em ADR e atualizar TASKS/ROADMAP ao encerrar um incremento.
- Não colocar segredos, payloads de clientes, arquivos privados ou sessões nos documentos ou commits.
- Aplicar mudanças no repositório real escolhido; não adicionar uma pasta de coordenação inteira ao Git.

## Fontes de confirmação

- [AGENTS.md](<../../AGENTS.md>)
- [README.md](<../../README.md>)
- [CONTINUE-AQUI.md](<../../CONTINUE-AQUI.md>)
- [package.json](<../../package.json>)
- [Gemfile](<../../Gemfile>)
- [db/schema.rb](<../../db/schema.rb>)
- [app/models](<../../app/models>)
- [app/javascript/dashboard](<../../app/javascript/dashboard>)
- [config/routes.rb](<../../config/routes.rb>)
