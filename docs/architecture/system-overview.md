<!-- jrc-operational-init:v1 -->
# Visão do sistema — JRC Conversas LAB2 — URA LAB

## Propósito e fronteira

Frente de laboratório de URA sobre o LAB2; conferir a release do núcleo antes de consolidar mudanças.

**Stack:** Ruby/Rails, Vue, PostgreSQL, Redis e Broker/Flow.

**Natureza:** Brownfield. **Tipo de raiz:** application.

## Fluxo lógico

Canal → inbox/contexto → Flow/URA → destino configurado → atendimento humano; pausa e atribuição seguem política da empresa.

Esta é uma visão de responsabilidades baseada em fontes locais, não um levantamento dos hosts efetivos. Versão em execução, topologia física, portas produtivas e imagem implantada não foram verificadas neste bootstrap.

## Controle de versões

- Data da leitura: 2026-11-13.
- Branch local: `codex/ura-padrao-lab2-20261104`.
- HEAD de origem antes da documentação: `a92f9bf8dd4a0b8828530f6c5d52d367449fe24b`.
- Origem Git: `https://github.com/ClaudioHideki/jrc-conversas-lab2.git`.
- [Contexto e versões declaradas](repository-context-init-v1.json).

Esse HEAD é a base documental observada e não será atualizado para fingir versão produtiva. A revisão documental, o software, o commit, a imagem publicada e a imagem em execução são informações distintas.

## Fontes atuais

- [AGENTS.md](<../../AGENTS.md>)
- [README.md](<../../README.md>)
- [package.json](<../../package.json>)
- [Gemfile](<../../Gemfile>)
- [db/schema.rb](<../../db/schema.rb>)

## Pendências conhecidas

- Reconciliar melhorias de URA com o núcleo mais recente sem sobrescrever atualizações.
- Validar atribuição por time/agente e pausa humana em ambiente autorizado.

O padrão de arquitetura JRC completo usa prancha integrada, fluxos, runtimes e quadro de versões com fontes; a referência visual aprovada é a arquitetura R03/R04 de 13/11/2026. Este índice não substitui aquelas pranchas nem os planos existentes.
