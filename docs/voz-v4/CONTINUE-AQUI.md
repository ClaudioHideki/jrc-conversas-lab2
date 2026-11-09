# Checkpoint Voz V4 — 09/11/2026

Continuar `codex/voz-v4-20261109`, preservando a base produtiva `0163e1ee...`, os commits incrementais e o diff preexistente do checkpoint `docs/release-integrada-jrc/CONTINUE-AQUI.md`. Não reiniciar nem reaplicar patches.

## Implementado nesta candidata

Shell global SIP, composição Voz de cinco abas, contexto autorizado e associação por identidade exata, popup de saída, presença/pausa nativa sincronizada, notas com conflito de versão/rascunho scoped, revisões transacionais e histórico paginado, controles táteis/DTMF/atalhos e PT-BR. Conferir MATRIZ-ADERENCIA e TESTES-E-EVIDENCIAS para limites e resultados por SHA.

## Próximo incremento verificável

1. Confirmar CI do HEAD exato, incluindo migration down/up isolados, 106+ specs Rails, Vitest, build e E2E. Corrigir qualquer falha antes da imagem.
2. Reconciliar schema gerado do banco descartável sem substituir schema mais novo do destino. Gerar candidata app pelo workflow existente, com SHA/base exatos e digest; não reconstruir NICO/Flows sem diff.
3. Completar atribuição/adiamento autorizados para atendimentos de Voz, com contrato de estados e regressões; não simular comandos de PABX.
4. Confirmar provedor real: origem do Call-ID, evento assinado, escopo de agente/ramal e retomada após reconnect. Comprovar correlação em chamada autorizada antes de promover vínculo live SIP a homologado.
5. Homologar áudio bidirecional, hold/retomada rejeitados e confirmados, transferência, DTMF, duas abas e ACW com ramais explicitamente autorizados. Os números das figuras não autorizam discagem.
6. Conectar dados autoritativos de gravação e restrições de serviços, com RBAC e estados desconhecido/erro explícitos; ampliar pesquisa de contato e roteamento de saída conforme capacidades reais.
7. Publicação produtiva somente após gates e janela segura sem chamadas/drain comprovados. Não encerrar chamadas para liberar deploy. Confirmar app/Sidekiq/SHA/schema após eventual aplicação autorizada.

## Broker independente

`BrokerJRCIA-source-audit` contém branch `codex/broker-device-name-20261109`, commit `d1ae956...`, CI 42632287978 aprovada. Compose/.env.example têm defaults Broker JRC/Chrome; nenhuma sessão foi alterada. O outro checkout `.worktrees/broker-connection-audit-20261104` permanece intacto.

## Restrições preservadas

Sem merge na main, testes telefônicos reais, alterações PABX/CCLX, migração/repareamento de WhatsApp ou mudanças produtivas sem os gates/autorização específicos. Backup/dump/restore/snapshot fora do escopo. Um ensaio sintético ou imagem publicada não prova telefonia operacional.
