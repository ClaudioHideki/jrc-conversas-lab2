<!-- jrc-operational-init:v1 -->
# Visão do sistema — JRC Conversas Precimech

## Propósito e fronteira

Frente de correção de retry WhatsApp Cloud/Meta para Precimech, isolada das políticas de QR/Evolution.

**Stack:** Ruby/Rails, Vue, PostgreSQL, Redis/Sidekiq e WhatsApp Cloud API.

**Natureza:** Brownfield. **Tipo de raiz:** application.

## Fluxo lógico

Mensagem → tentativa Cloud API → recibo/erro → política durável por provedor → reconciliação ou retry elegível.

Esta é uma visão de responsabilidades baseada em fontes locais, não um levantamento dos hosts efetivos. Versão em execução, topologia física, portas produtivas e imagem implantada não foram verificadas neste bootstrap.

## Controle de versões

- Data da leitura: 2026-11-13.
- Branch local: `codex/hotfix-precimech-whatsapp-retry-20261111`.
- HEAD de origem antes da documentação: `549102e44a0141d088e88551cb552d1157c17076`.
- Origem Git: `https://github.com/ClaudioHideki/jrc-conversas-lab2.git`.
- [Contexto e versões declaradas](repository-context-init-v1.json).

Esse HEAD é a base documental observada e não será atualizado para fingir versão produtiva. A revisão documental, o software, o commit, a imagem publicada e a imagem em execução são informações distintas.

## Fontes atuais

- [AGENTS.md](<../../AGENTS.md>)
- [README.md](<../../README.md>)
- [package.json](<../../package.json>)
- [Gemfile](<../../Gemfile>)
- [db/schema.rb](<../../db/schema.rb>)
- [docs/superpowers/specs/2026-11-11-whatsapp-durable-retry-design.md](<../../docs/superpowers/specs/2026-11-11-whatsapp-durable-retry-design.md>)

## Pendências conhecidas

- Preservar o hotfix em andamento e distinguir rejeição, aceite remoto e estado incerto.
- Validar retry por provedor e evitar duplicação de mensagens aceitas.

O padrão de arquitetura JRC completo usa prancha integrada, fluxos, runtimes e quadro de versões com fontes; a referência visual aprovada é a arquitetura R03/R04 de 13/11/2026. Este índice não substitui aquelas pranchas nem os planos existentes.
