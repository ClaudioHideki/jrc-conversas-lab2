# Recibo LIVE nativo: plano do incremento local

Contrato aprovado: `Broker/docs/implementation/live-ingress-receipt-v1-20261116.md`, protocolo `jrc-live-ingress/1`.

1. RED de texto: capability, autoridade atual, hash canônico, rollback, deduplicação e consulta imutável independente de atributos editáveis.
2. Migração aditiva `20261116190000`, chave única de origem, identidade protegida no PostgreSQL e modelo. Recibos/objetos KEEP; rollback operacional pausa admissão, preservando pendências.
3. Receiver de texto usa apenas autoridade registrada atual e `Messages::MessageBuilder` normal, dentro da mesma transação do recibo. LIVE outgoing não representa ator humano.
4. RED de mídia: reserva durável `MEDIA_PENDING`, mensagem nula, escrow privado limitado a16MiB/arquivo e64MiB/Account sob lock. Nenhum callback antes de custódia.
5. Executor/recovery por ID; valida token original e escopo antes do acesso privado e novamente antes do COMMIT. Verifica bytes reais antes de criar mensagem. Não sobrescreve objeto corrompido. Limpa escrow somente junto de PERSISTED.
6. GREEN focal Rails, isolamento/concorrência/imutabilidade e limites; regressões de histórico, callbacks e estado outbound. Atualização dos runners HTTP somente coordenada com responsável pelo Broker.
7. Delta aprovado de interoperabilidade: origin_context nullable e imutável para novas V2, source lock comum, reuso estrito de recibos/bytes sem novos callbacks. Recibos antigos sem contexto não são promovidos. ADR0002 registra a decisão e o bloqueio de lifecycle hard delete antes de release.
8. Delta aprovado de clocks: occurred_at opcional sem alterar hashes antigos; created_at de origem e atividade monotônica. Não lidas por published_at servidor imutável apenas na publicação normal, mantendo adoção histórica silenciosa. Cobrir badges/cache/filtros, cursor manual, websocket pós-COMMIT e isolamento sem N+1; manter janela24h de origem.

Não usa importador histórico, não altera visibilidade, não reconcilia UNKNOWN legado sem prova nativa, não envia WhatsApp e não executa produção/migração produtiva. Nenhuma credencial em Git, artefatos ou jobs. Testes locais Ruby3.4.4 são compatibilidade de runner, não aceite do runtime produto3.4.12. Build frontend anterior permanece bloqueado pelos recursos locais documentados.
# Adendo: relógio de publicação na leitura da interface

O JSON de leitura de mensagens e o websocket passam a expor `broker_published_at` (segundos Unix, ou nulo), derivado exclusivamente de `JrcBrokerLiveReceipt.published_at` imutável, com o mesmo `message_id` e `account_id`, em estado PERSISTED. A projeção paginada usa subconsulta escalar indexada, sem carregar envelopes e sem N+1. A projeção nunca é persistida na mensagem, enviada no webhook ou usada como autoridade de intenção humana. Mensagens genéricas e adoções históricas continuam com valor nulo. A interface usa esse relógio somente para separar lidas/não lidas; cronologia, horário exibido e janela de 24 horas conservam `created_at` original.

Em 16/11/2026, helper e MessagesView passaram 10/10; lint dos três arquivos focais passou. A primeira execução RED comprovou a falha funcional de partição; a fixture Vue foi completada com store sintético. A validação Ruby3.4.12, armazenamento privado e build final seguem no workflow de candidata, sem publicação de imagens ou deploy.
