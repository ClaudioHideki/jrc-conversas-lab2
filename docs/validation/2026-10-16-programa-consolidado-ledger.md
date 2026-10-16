# Programa consolidado: registro verificável

Esta atualização ainda não equivale ao programa completo nem está liberada para publicação. Última orientação: manter próximos desenvolvimentos locais até concluir o corte consolidado; não ativar bot nem alterar o servidor atual. JRC/NICO continuam na candidata separada do trabalho do outro desenvolvedor.

## Incrementos deste desenvolvimento

| Componente | Commit local | Resultado |
|---|---|---|
| Broker: handoff cooperativo | eb933b4 | Aceita política de time conhecida true/false e verifica agente efetivo no time/caixa; mantém humano |
| Broker: troca concorrente de agente | 8277b45 | Confirmação vinculada ao alvo validado; mudança durante consulta fica UNKNOWN sem repetir POST |
| JRC: Customer360 | 86f08ce4 | Mapa sob demanda de relações autorizadas, contagem distinta/amostra10 e acesso às abas existentes |
| NICO: caixa Broker legada | 9ff3354b | Requer adoção verificada antes de envio público; preserva notas e aprovação coordenada |
| NICO: radar e filtro de leitura | 56f13dfd | Backlog completo, categorias determinísticas, histórico independente de Relacionamento e custom roles de administradores aplicados |

O incremento anterior de análise rastreável 8859f585 já estava publicado antes da orientação de aguardar o corte completo. Nenhum dos commits acima foi enviado nesta etapa.

## Evidência e limites

- Broker: 33 testes de integração; typecheck aprovado. Suíte geral posterior: 407 arquivos/3122 testes passaram, um timeout no relatório de segurança; o arquivo isolado passou com seis testes. Rodada anterior completa: 408 arquivos/3123 aprovados. Nenhuma alteração do gerador ou de seu timeout.
- JRC: 15 exemplos Rails Customer360, oito de interface. Radar/filtro/domínio: 43 exemplos aprovados. Bindings NICO20 e OperatorSession20 aprovados em rodadas focais. Commit gate: 18 exemplos de concorrência aprovados sem pending em PostgreSQL descartável.
- Revisões independentes produziram regressões reais de concorrência, autorização e histórico; achados Important foram corrigidos com RED/GREEN. Não equivalem a homologação real de WhatsApp/Meta/chamadas.
- Manifestações de composição/ownership regeneradas e verificadas para os fontes candidatos. Compose, ENV, schema e digests de produção permanecem sem alteração nesta etapa.

## Ainda não concluído

1. Ciclos remotos QR/Chatwoot: o mapeamento atual admite apenas uma conversa central por conversa física. Uma nova conversa central do mesmo contato pode resultar em CHATWOOT_CONVERSATION_ALREADY_BOUND. Não substituir o vínculo: jobs, recibos, controles, sessões e mensagens antigas precisam manter seu destino. Necessita modelo de ciclos/correlação e migração próprios, com teste de callbacks antigos, mensagens em trânsito e isolamento. A investigação não constitui correção implementada.
2. Importação histórica: completar cursor/checkpoint estável e provar cobertura sem perda/repetição sob novas mensagens; disponibilidade do catálogo/grupos não comprova importação integral do WhatsApp.
3. Público em lote, recorrência e cadência: ainda precisam de inscrição versionada, prévia congelada, recibo por item e cancelamento por resposta/intervenção humana.
4. Jornadas guiadas e nós adicionais: switch tipado, comandos de domínio/eventos no Flow, integrações de escrita autorizadas, agente limitado e conhecimento por empresa. Nós existentes não foram declarados universalmente funcionais.
5. Agendamento de serviços e voz contínua/transporte de chamadas: não foram implementados neste corte. Ditado/leitura existentes e PABX não comprovam atendimento IA em ligação WhatsApp.
6. Fechamento consolidado: verificar todos os adaptadores/contratos, build, CI remoto e imagens somente após concluir as entregas. Homologação em servidor separado depende de configuração dos tenants A/B, Chatwoot externo e ativos Meta/chamadas. Capacidade de 10 mil conexões exige carga real e dimensionamento; não é garantida por testes locais.

Fontes de planejamento: `docs/superpowers/specs/2026-10-16-nico-jornada-candidata-design.md` e relatórios públicos da comparação Astra em `entregas/2026-10-16-videos-astra-comparacao-jrc.json` no workspace principal. Não houve cópia de código privado do concorrente nem engenharia de um serviço sem acesso autorizado.
