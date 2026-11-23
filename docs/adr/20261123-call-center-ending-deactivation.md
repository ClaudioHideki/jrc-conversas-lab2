# Desativação das automações por encerramento — 23/11/2026

Decisão explícita do usuário: desativar uma automação também bloqueia ações ainda pendentes. Ações concluídas e histórico são preservados.

Cada origem continua vinculada à versão exata da regra. A primeira versão posterior que desativa ou remove a regra bloqueia suas pendências e tentativas futuras. Reativar a mesma regra não ressuscita essas pendências; novas origens podem usar a nova versão ativa. Editar uma regra ativa não redireciona parâmetros de origens anteriores.

O bloqueio é derivado do histórico imutável privado, sem regravar versões antigas, criar concessões ou inserir dados retroativos. Sua consulta usa parâmetros preparados e filtrados. Ela é evidência de cancelamento, nunca autorização. O futuro executor deve verificar a barreira dentro da transação nativa da conta, depois de revalidar as permissões atuais do agente original e os escopos da origem e destino, somente antes de efeitos pendentes ou novas tentativas. Leituras de recibos já concluídos não devem aplicar esse bloqueio.

Este incremento prepara configuração e consulta da barreira. Não comprova cancelamento físico de ações, execução nos destinos, recibos, editor operacional ou homologação externa. Os testes nativos estão preparados e aguardam execução. Nenhuma regra ou permissão real foi ativada.
