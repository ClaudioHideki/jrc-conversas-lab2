<!-- jrc-operational-init:v1 -->
# Regras de negócio — JRC Conversas Precimech

Estas regras documentam o escopo conhecido e preservam as decisões específicas anteriores; não ativam comportamentos no produto.

- Restringir a política de retry ao provedor e aos erros comprovadamente elegíveis.
- Preservar a rastreabilidade entre tentativa, source_id e retorno remoto.
- Não reenviar mensagem aceita ou de resultado incerto sem reconciliação.

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
- [docs/superpowers/specs/2026-11-11-whatsapp-durable-retry-design.md](<../../docs/superpowers/specs/2026-11-11-whatsapp-durable-retry-design.md>)
