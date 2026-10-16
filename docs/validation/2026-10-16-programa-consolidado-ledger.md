# Programa consolidado: registro verificável

Esta atualização ainda não equivale ao programa completo nem está liberada para publicação. Última orientação: manter próximos desenvolvimentos locais até concluir o corte consolidado; não ativar bot nem alterar o servidor atual. JRC/NICO continuam na candidata separada do trabalho do outro desenvolvedor.

## Incrementos deste desenvolvimento

| Componente | Commit local | Resultado |
|---|---|---|
| Broker: handoff cooperativo | eb933b4 | Aceita política de time conhecida true/false e verifica agente efetivo no time/caixa; mantém humano |
| Broker: troca concorrente de agente | 8277b45 | Confirmação vinculada ao alvo validado; mudança durante consulta fica UNKNOWN sem repetir POST |
| Broker: ciclos físicos Chatwoot | 8527aed | Novo atendimento mantém mapa/recibos antigos; intervenção humana histórica pausa corrente na admissão; envio concorrente e autoridade automatizada protegidos |
| Broker: switch tipado | 51dbab1 | Decisão escalar estrita com casos estáveis/default, mesmo catálogo, motor, simulação e canvas |
| JRC: Customer360 | 86f08ce4 | Mapa sob demanda de relações autorizadas, contagem distinta/amostra10 e acesso às abas existentes |
| NICO: caixa Broker legada | 9ff3354b | Requer adoção verificada antes de envio público; preserva notas e aprovação coordenada |
| NICO: radar e filtro de leitura | 56f13dfd | Backlog completo, categorias determinísticas, histórico independente de Relacionamento e custom roles de administradores aplicados |

O incremento anterior de análise rastreável 8859f585 já estava publicado antes da orientação de aguardar o corte completo. Nenhum dos commits acima foi enviado nesta etapa.

## Evidência e limites

- Broker: handoff33 testes de integração. Ciclos18, histórico10, interface41 e QR unitário17 aprovados; typecheck aprovado. Suíte geral dos ciclos: 408 arquivos/3125 testes aprovados em331,05s, antes do último ajuste focal do histórico (que recebeu os dez testes PostgreSQL/17 unitários próprios). Regressões adicionais registradas no documento focal do Broker. Nenhuma alteração do gerador de segurança ou de seu timeout.
- JRC: 15 exemplos Rails Customer360, oito de interface. Radar/filtro/domínio: 43 exemplos aprovados. Bindings NICO20 e OperatorSession20 aprovados em rodadas focais. Commit gate: 18 exemplos de concorrência aprovados sem pending em PostgreSQL descartável.
- Revisões independentes produziram regressões reais de concorrência, autorização e histórico; achados Important foram corrigidos com RED/GREEN. Não equivalem a homologação real de WhatsApp/Meta/chamadas.
- Manifestações de composição/ownership JRC regeneradas e verificadas para os fontes candidatos. Broker acrescenta migration0066 somente para índice e probe correspondente; não foi aplicada ao servidor. Compose, ENV e digests de produção permanecem sem alteração nesta etapa. Nenhuma migration JRC nova.
- Editor embutido JRC regenerado a partir do fonte commitado51dbab1 (198 inputs; scanner sem achados). Teste real de navegador exclusivamente local:7 cenários aprovados, incluindo switch, CSS isolado e restrição de publicação; zero requisições externas. Fontes, manifestos e artefatos ficam na candidata separada, sem atualizar servidor. O formato do switch legado do JRC não foi convertido nem alterado.

## Ainda não concluído

1. Ciclos remotos QR/Chatwoot: correção implementada/verificada localmente no commit8527aed; falta sua homologação real no ambiente separado. Migração0066 deve acompanhar a imagem futura. Não substituir vínculos manualmente nem ativar bot no servidor atual.
2. Importação histórica: completar cursor/checkpoint estável e provar cobertura sem perda/repetição sob novas mensagens; disponibilidade do catálogo/grupos não comprova importação integral do WhatsApp.
3. Público em lote, recorrência e cadência: ainda precisam de inscrição versionada, prévia congelada, recibo por item e cancelamento por resposta/intervenção humana.
4. Jornadas guiadas e nós adicionais: switch tipado implementado no Broker e pacote de editor candidato JRC; falta homologação no servidor. Comandos de domínio/eventos no Flow, integrações de escrita autorizadas, agente limitado e conhecimento por empresa continuam pendentes. Nós existentes não foram declarados universalmente funcionais.
5. Agendamento de serviços e voz contínua/transporte de chamadas: não foram implementados neste corte. Ditado/leitura existentes e PABX não comprovam atendimento IA em ligação WhatsApp.
6. Fechamento consolidado: verificar todos os adaptadores/contratos, build, CI remoto e imagens somente após concluir as entregas. Homologação em servidor separado depende de configuração dos tenants A/B, Chatwoot externo e ativos Meta/chamadas. Capacidade de 10 mil conexões exige carga real e dimensionamento; não é garantida por testes locais.

Fontes de planejamento: `docs/superpowers/specs/2026-10-16-nico-jornada-candidata-design.md` e relatórios públicos da comparação Astra em `entregas/2026-10-16-videos-astra-comparacao-jrc.json` no workspace principal. Não houve cópia de código privado do concorrente nem engenharia de um serviço sem acesso autorizado.
