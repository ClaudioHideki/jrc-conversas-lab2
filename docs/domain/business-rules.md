<!-- jrc-operational-init:v1 -->
# Regras de negócio — JRC Conversas LAB2 — URA LAB

Estas regras documentam o escopo conhecido e preservam as decisões específicas anteriores; não ativam comportamentos no produto.

- Preservar identidade, contexto, pausa humana e destino por caixa.
- Atribuir conforme política configurada e elegibilidade do agente; não copiar IDs entre empresas.
- Não considerar um Flow salvo como robô ativado ou entrega homologada.

## Regras de manutenção

- Preservar as regras específicas preexistentes do projeto e os trabalhos concorrentes.
- Separar código implementado, teste local, CI, imagem publicada, implantação e aceite operacional.
- Registrar decisões relevantes em ADR e atualizar TASKS/ROADMAP ao encerrar um incremento.
- Não colocar segredos, payloads de clientes, arquivos privados ou sessões nos documentos ou commits.
- Aplicar mudanças no repositório real escolhido; não adicionar uma pasta de coordenação inteira ao Git.

## Fontes de confirmação

- [AGENTS.md](<../../AGENTS.md>)
- [README.md](<../../README.md>)
- [package.json](<../../package.json>)
- [Gemfile](<../../Gemfile>)
- [db/schema.rb](<../../db/schema.rb>)
