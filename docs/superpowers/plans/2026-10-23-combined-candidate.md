# Candidata integrada JRC - plano de consolidacao

> **For agentic workers:** Use superpowers:executing-plans para concluir cada gate abaixo. Nao mesclar na principal nem implantar antes do aceite da revisao exata.

**Goal:** Publicar uma imagem candidata que preserve as atualizacoes de Broker/clientes/campanhas e Atendimento/Projetos/Service Desk/voz.

**Architecture:** Mesclar os dois commits conhecidos na branch candidata isolada existente. Preservar os contratos e os modulos de ambos os lados; produzir uma imagem do resultado apos regressao ampliada.

**Tech Stack:** Rails, PostgreSQL/Redis de teste, Vue/Vitest, GitHub Actions e GHCR por SHA/digest.

**Spec:** Pedido do usuario para consolidar as imagens e preservar todos os desenvolvimentos, junto ao plano `2026-10-23-broker-inbox-autoregistration.md` e ao diff dos commits abaixo.

## Revisoes e limites

- Nosso candidato: `9ed1e7e4d06a2fc8cf5f06e4b5932b19c4434541`; CI39972519969 aprovado nos dois jobs. Backend305/305 e frontend completo, sem pendencias.
- Revisao paralela: `1f00e13cc0c39e1c62f568df75672013f8182142`, com `202c84cc` (consolidacao de Service Desk, Projetos, central de voz e navegacao de clientes) e `1f00e13c` (SIP independente da ativacao do Contact Center).
- Base comum: `abc1f7c57f55a7d9871101cd5b70c8b93becc7ca`. As revisoes divergem; nenhuma imagem anterior contem automaticamente o outro conjunto.
- A publicacao pendente39974750066, de nossa revisao isolada, foi cancelada. A execucao39973204477 de outro executor foi preservada. Nenhum deploy foi realizado.

## Passos

- [x] Confirmar source limpo e buscar o commit paralelo exato, sem atualizar a principal.
- [x] Simular e iniciar merge sem commit:173 arquivos do incoming. Um unico conflito em `pt_BR/jrcProjects.json`.
- [x] Resolver o JSON por uniao de tres vias. Foram14 valores novos conflitantes; preservar a redacao da nova interface nesses valores, manter as demais chaves de ambos os lados e validar JSON.
- [x] Revisar estaticamente traducoes/parametros e intersecoes entre navegacao, Atendimento, clientes e vinculos Broker. Projetos566/566, ServiceDesk1351/1351 e Calls192/192 sem novas lacunas ou divergencias de parametros; CRM/NICO preservados.
- [x] Ampliar o job PostgreSQL para requests Contact Center/Operacoes/Service Desk e services Service Desk, alem das suites Broker/clientes/campanhas ja aprovadas. Piso305 exemplos e zero falhas/pendencias; manter PostgreSQL descartavel por job/run, frontend completo e branch restrita.
- [x] Validar workflow, diff e merge; registrar commit candidato `05c0a5e8bd2e4d1760925dfa3dbc81a9540ce29e` e iniciar o CI `39978603091` da revisao resultante.
- [ ] Corrigir qualquer regressao por causa raiz, sem remover suites, enfraquecer permissoes ou atualizar snapshots para obter verde.
- [ ] Publicar a imagem por SHA/digest apos gates aprovados. Conferir a versao atualmente instalada antes de preparar qualquer deploy, preservando atualizacoes posteriores de outros trabalhos.

## Verificacao complementar

- Workflow validado como YAML com chaves unicas; nove blocos `run` passaram em `bash -n` dentro do PostgreSQL local de teste. Nenhum bloco foi executado nessa verificacao de sintaxe. Prettier aprovado.
- A revisao encontrou uma falha real anterior de agrupamento: caixas `Channel::Api` com `jrc_broker_bound: true` eram classificadas por nome/atributos, ignorando o vinculo autenticado publicado pelo backend. Os testes novos reproduziram cinco falhas; a correcao minima passou nos65 exemplos do helper e nos40 exemplos adjacentes (duas suites InboxList e HoyaInboxWorkspace). ESLint dos dois arquivos e diff check aprovados. A correcao classifica a caixa; nao simula conexao ou entrega de mensagens.
- A invalidacao de cache existente cobre o `touch` do vinculo e atualiza as caixas; nao foi necessario criar outro evento ou cache.

## Resultado do primeiro CI integrado e ajuste minimo

- A candidata `05c0a5e8` contem `202c84cceac70a2480f942c80e27ce30b943beb0` e `1f00e13cc0c39e1c62f568df75672013f8182142`; a auditoria dos refs nao encontrou outra revisao posterior que exija novo merge. O principal implementer confirmou `202c84cc` no Rails instalado, em leitura separada; isso nao prova a instalacao da candidata.
- O job Rails `120499661872`, no CI `39978603091`, terminou com **1055 exemplos, zero falhas e 11 pendentes**, sem erros fora dos exemplos. A assercao de zero pendencias barrou corretamente o job; nao ha aprovacao para gerar a imagem integrada.
- As pendencias sao testes concorrentes de Service Desk sem o opt-in exigido e, em seis casos, fora da lista exata de bancos descartaveis existente. O ajuste usa `JRC_SD_CONCURRENCY=1` e o perfil literal `jrc_rel_sd_r345_concurrency_test`, como em `service-desk-global-native.yml`. O isolamento continua sendo o PostgreSQL efemero criado por job/run, com host `127.0.0.1`; nome literal, `RAILS_ENV=test` e ausencia de `DATABASE_URL` sao verificados antes de criar o banco.
- Todas as suites, o piso305 e as assercoes de zero falhas/pendencias ficam preservados. Nao ampliar a allowlist nem alterar testes do produto. Validar YAML, Prettier, sintaxe dos blocos Bash e diff antes da proxima revisao.
- O Vitest completo desta execucao terminou aprovado antes do push corretivo: **580 arquivos, 5703 testes, zero falhas e zero pendentes**, em598,21s; a preservacao de fonte/snapshots/lockfiles tambem passou. A evidencia foi preservada, sem cancelar a execucao.
- O ajuste de CI passou em YAML com chaves unicas, verificacao dos12 caminhos RSpec e preservacao dos gates/pins/frontend, Prettier, `bash -n` dos nove blocos sem execucao e `git diff --check`. Exigir novo CI completo verde na revisao corrigida antes da publicacao por SHA/digest.

O gate Broker separado encerrou3394/3395, com uma falha de inventario documental em revisao; nao esta aprovado para commit/publicacao. Este merge nao altera esse repositorio, nao importa clientes reais, nao inicia campanhas e nao modifica as reservas do NICO.
