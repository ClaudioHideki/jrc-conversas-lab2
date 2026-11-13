<!-- jrc-operational-init:v1 -->
# Visão do sistema — JRC Conversas LAB2 — Grupo JRC

## Propósito e fronteira

Produto omnichannel base completo do Grupo JRC, com atendimento, canais, distribuição e integrações; referência para melhorias genéricas.

**Stack:** Ruby/Rails, Vue, Vite, PostgreSQL, Redis/Sidekiq, ActiveStorage/S3, SIP e APIs Broker/Meta.

**Natureza:** Brownfield. **Tipo de raiz:** application.

## Fluxo lógico

Canal → recepção/outbox transacional → Account/inbox/conversa → agente autorizado; mídia privada e integração Broker preservam identidade e recibos.

Esta é uma visão de responsabilidades baseada em fontes locais, não um levantamento dos hosts efetivos. Versão em execução, topologia física, portas produtivas e imagem implantada não foram verificadas neste bootstrap.

## Controle de versões

- Data da leitura: 2026-11-13.
- Branch local: `codex/whatsapp-history-order-20261111`.
- HEAD de origem antes da documentação: `787dff99f087aec453e40dd19497758704a89e1a`.
- Origem Git: `https://github.com/ClaudioHideki/jrc-conversas-lab2.git`.
- [Contexto e versões declaradas](repository-context-init-v1.json).

Esse HEAD é a base documental observada e não será atualizado para fingir versão produtiva. A revisão documental, o software, o commit, a imagem publicada e a imagem em execução são informações distintas.

## Fontes atuais

- [AGENTS.md](<../../AGENTS.md>)
- [README.md](<../../README.md>)
- [CONTINUE-AQUI.md](<../../CONTINUE-AQUI.md>)
- [package.json](<../../package.json>)
- [Gemfile](<../../Gemfile>)
- [db/schema.rb](<../../db/schema.rb>)
- [app/models](<../../app/models>)
- [app/javascript/dashboard](<../../app/javascript/dashboard>)
- [config/routes.rb](<../../config/routes.rb>)

## Pendências conhecidas

- Reconciliar conversas por caixa e a política de acesso Minhas/compartilhadas/exclusivas.
- Manter homologação de voz, histórico e mídias distinta de teste sintético e de publicação.

O padrão de arquitetura JRC completo usa prancha integrada, fluxos, runtimes e quadro de versões com fontes; a referência visual aprovada é a arquitetura R03/R04 de 13/11/2026. Este índice não substitui aquelas pranchas nem os planos existentes.
