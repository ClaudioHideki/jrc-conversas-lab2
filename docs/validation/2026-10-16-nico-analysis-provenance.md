# NICO: procedência da análise — primeira entrega candidata

Branch: `codex/nico-jornada-candidato-20261016`. Base integrada: produção `98a4be7714be41d33bf9ff52b254ebb773864769` e paginação candidata `8edb1f30fb3364373f0afba357559c884ca5d57a`. Ambos confirmados como ancestrais. O merge ocorreu sem conflitos.

## Alteração e uso

No painel NICO, a análise de sentimento já existente passa a explicar que o resultado é inferido e apresenta quantidade, modelo, início/fim da amostra e textos truncados. Não há novo menu nem serviço independente. Os detalhes e o download preservam o relatório anterior, acrescentando versão, IDs e hash da amostra efetivamente enviada.

O JRC calcula a procedência e rejeita evidência que aponte para mensagem fora da janela, mesmo se um runtime antigo aceitar a resposta. Referência válida não comprova a conclusão da IA. O contrato enviado ao runtime NICO não mudou; não há alteração em `services/nico-runtime` neste incremento.

## Evidência local

- UI RED inicial: 1 falha por ausência do painel de procedência e 41 testes preservados.
- Rails RED: 7 exemplos, 2 falhas esperadas — metadados do modelo sobrescreviam procedência e evidência privada não era recusada na fronteira JRC.
- Rails GREEN inicial: 7 exemplos, 0 falhas.
- Após refatoração/estilo: `conversation_sentiment_spec.rb` + `context_builder_spec.rb`: **10 exemplos, 0 falhas**, PostgreSQL/Redis exclusivos e dados sintéticos.
- Revisão independente detectou `Intl.DateTimeFormat('pt_BR')` inválido. Reproduzido em teste: 1 falha/42 preservados, `RangeError`. Correção segue normalização já existente no NICO.
- UI final: **85 testes, 8 arquivos, 0 falhas**, incluindo en/pt_BR, relatórios antigos, voz e sessão do operador.
- RuboCop dos dois arquivos Ruby: **2 arquivos, nenhuma ocorrência**, após normalizar finais de linha do runner Linux.
- ESLint focal: sem erros; 16 avisos anteriores no `JrcCopilotPanel.vue` foram preservados, sem formatação incidental do painel.
- JSON de tradução válido; `git diff --check` aprovado.

Execução local pelo runner Docker descartável `jrc-jornada-tests-20261016`, banco `jrc_jornada_candidate_test`, rede `jrc-jornada-20261016`. Nenhum dado de cliente ou credencial de produção foi usado.

## Revisão e limites

Revisão somente leitura pelo agente `review_nico_provenance_20261016`. Único achado importante: locale de datas, corrigido com RED/GREEN. Duas observações menores permanecem explícitas: paridade do catálogo pt_BR já tinha lacunas e os seis textos novos usam o fallback en, conforme a regra do repositório de editar apenas o catálogo en; falta um caso dedicado a evidência de mensagem pública mais antiga que a janela, embora a seleção das últimas 100 e a rejeição de IDs externos tenham cobertura separada.

Este incremento não altera Docker/Compose, banco/schema, dependências ou ENV em relação à base 98a. Não ativa bot, não publica/vincula Flow, não envia mensagem e não muda o servidor. Os workflows foram estendidos para testar a candidata, não para implantar produção.

Não certifica handoff, transporte de voz, Meta, campanhas, Chatwoot externo ou escala. As etapas seguintes do programa continuam no plano; este documento não declara o programa completo. CI remota, imagem candidata e homologação no novo servidor ainda exigem seus resultados próprios.
