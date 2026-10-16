# Plano: NICO e jornada candidata

Spec: `docs/superpowers/specs/2026-10-16-nico-jornada-candidata-design.md`.
Execução direta autorizada pelo usuário, em incrementos. Não alterar produção ou ativar bot Broker. A primeira entrega é análise rastreável; as seguintes não estão declaradas implementadas.

## Restrições globais

- Branch candidata `codex/nico-jornada-candidato-20261016`; preservar ancestral 98a4be7 e paginação 8edb1f3.
- Testes locais sintéticos; nenhum envio, publicação/vínculo de automação ou alteração de flags no servidor.
- Reutilizar políticas e serviços atuais. Metadados de origem vêm do servidor, não do modelo.
- Não alterar digest de produção nem colocar credenciais nos artefatos.

## Tarefa 1 — integrar base atual

- [x] Conferir árvore limpa e histórico.
- [x] Criar branch candidata no worktree isolado existente e integrar 98a4be7 preservando paginação.
- [x] Confirmar ancestralidade e diferença de Compose/entrada de serviços; não alterar configuração de implantação.

## Tarefa 2 — relatório rastreável

Arquivos: `app/services/jrc_ai/conversation_sentiment.rb`, `spec/services/jrc_ai/conversation_sentiment_spec.rb`, painel em `app/javascript/dashboard/components-next/jrcCopilot/`, tradução `locale/en/jrcNico.json` e testes NICO.

Interface: preservar campos existentes; adicionar versão 1, `inferred: true`, janela com IDs/limites/truncamento e rejeitar evidências com IDs externos à amostra. O runtime continua recebendo o mesmo contrato de mensagens.

- [x] Escrever e executar testes RED de procedência e evidência fora da amostra; preservar teste de relatório antigo.
- [x] Implementar metadados calculados pelo servidor, sem mutação de domínio.
- [x] Exibir aviso, contagem, modelo e período no painel existente, com testes de renderização.
- [x] Executar RSpec focal e suite NICO de interface; lint focal e `git diff --check`.
- [x] Registrar resultados e limitações antes de commit em `docs/validation/2026-10-16-nico-analysis-provenance.md`.

## Tarefa 3 — CI da candidata

Arquivo: `.github/workflows/nico-broker-candidate.yml`. Aceitar apenas branches candidatas explicitamente nomeadas, exigir ancestral 98a4be7 para a nova candidata e incluir RSpec de sentimento. Preservar o workflow antigo para a candidata anterior. Imagens continuam por SHA, sem alterar tags de produção.

- [x] Atualizar filtro/validação e incluir a regressão nova nos workflows NICO e Flow/QR.
- [ ] Conferir diff, publicar somente branch candidata e acompanhar CI quando houver acesso disponível.

## Entregas seguintes

Cada uma recebe plano focal antes do código: coordenação e vínculos; radar/grafo Customer360; público/recorrência/cadência; comandos/eventos; agente limitado/conhecimento; voz por capacidades. Desenvolver na mesma candidata sem certificar antecipadamente partes dependentes de ativos externos ou servidor de homologação.

## Revisão

Verificar: notas privadas excluídas; metadados não sobrescritos pelo provedor; evidências externas não marcadas válidas; relatórios antigos legíveis; nenhuma migração/configuração ativa bot ou muda servidor. Testes de análise não comprovam handoff, chamadas, Meta ou escala.
