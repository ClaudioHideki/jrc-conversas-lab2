# Candidata integrada — 02/11/2026

Branch: codex/release-integrada-specs-20261102. Histórico preservado: 89d87ccb (outbox/Sidekiq), ab8f672b (ajuste APT preexistente), merge19d28b72 (44commits de Cláudio/e4a6a007) e merge57efc6e1 (12commits Backoffice50f7f07d já em produção). Não voltar a default antiga128243d; publicar seguindo a branch efetiva do Grupo JRC confirmada. Broker relacionado: PR6, candidata7c49037, CI exata pendente. O pedido atual autoriza merge/publicação/Dokploy após gates; backup/dump/restore, envio real, replay UNKNOWN e carga histórica produtiva ficam excluídos.

## Alterações deste incremento

- Callback durável conserva identidade de campanha, trata adiamento sem consumir tentativa e exige confirmação HTTP real. Wrappers de Survey/ServiceDesk não geram ACK falso ao suprimir erro/recusar I/O. UNKNOWN fica terminal sem replay cego; campanha legada sem obrigação mantém fallback.
- Cards de conexões autorizadas, consulta de saúde limitada, popup reusando painel de pareamento/reconexão, CTA de novo número sem formulário aninhado e descarte de estado sensível ao revogar/trocar Account/logout.
- Distribuição por conexão sobre HumanAssignment existente: times da mesma Account ordenados, rodízio/prioridade/direto, capacidade agregada, presença/pausa e concorrência. Mantém inbox de origem, não redistribui conversas atribuídas; vigência só após salvar. Auditoria antes/depois na mesma transação; API e formulário admin sem ampliar acesso implicitamente.
- Reconciliação DataImport somente leitura com totais desconhecidos, identidade entre runs, mappings ausentes/cross-account, tipos fora de escopo e mídia explicitamente não verificada. Não confundir com Central completa ou carga finalizada.
- Editor nativo gerado do Broker commitado; contratos/catálogo compartilhados, limite opcional de tentativas de menu e saída de esgotamento. Preservar motores legados e registrar suas limitações de versionamento/simulação.

## Testes e gates

Antes da refatoração:73 exemplos de integridade/distribuição/importação e210 de callback/campanhas/integração sem falhas, com sobreposição. Após refatoração:267 exemplos Rails,0falhas; inclui concorrência real no PostgreSQL. Uma tentativa de runner usou database de teste anterior e parou por migrations pendentes; reexecutada com POSTGRES_DATABASE=jrc_durable_review_test explícito. Nenhuma migration produtiva executada.

Frontend:17files/89tests,0falhas. Lint candidato0erros/34warnings; quatro áreas têm2erros preexistentes em AgentFlowsPage no-plusplus, confirmados em HEAD. Não marcar lint integral como verde. Ruby lint comparado ao baseline, sem desabilitar cops novos; confirmar relatório final antes de publicar. YAML dos workflows validado com Psych; CI exata e build oficial ainda necessários.

## Schema e compatibilidade

Migrations20261102090000 (obrigações de webhook) e20261102100000 (auditoria de distribuição); schema consolidado sobre20261101200000 do Backoffice com constraints/FKs. Foram aplicadas somente no banco sintético. Não remover ledger pendente em contingência nem usar worker antigo que ignore a obrigação como solução de entrega. Preservar0079 do Broker e revisar compatibilidade dos consumidores antes de rollout.

## Pendências explícitas

WA: histórico completo, calendário/fallback configurável, métricas e jornada integral ainda parciais. Flow: seguir MVP e roadmap; engine canônica não equivale à homologação de executor legado LAB2. Migração: fontes reais indefinidas não bloqueiam construir software com fixtures, mas ainda não há Central de todos os domínios nem aceite/carga. Engine Evolution, custódia integral, dois Chatwoots reais, TLS end-to-end e piloto50/30dias não encerrados por testes sintéticos.

Próximo: CI/Rails completos por SHA e revisão das lacunas internas. Publicar apenas componentes aprovados com escopo/flags explícitos; não declarar todos os documentos concluídos por contagem de testes. Relatórios e logs sintéticos ficam no pacote externo de evidências, sem ENV/payload real.
