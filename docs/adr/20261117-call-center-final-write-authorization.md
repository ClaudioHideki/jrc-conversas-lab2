# Call Center: revalidar autorização após esperar por locks administrativos

Status: decisão técnica preparada antes da implementação.

A nova elegibilidade e a revogação de perfil são verificadas por requisição.
ConfigurationWrite, porém, pode aguardar locks de unidade/fila depois de
capturar a política e o escopo do ator. Uma revogação durante essa espera
não pode ser ignorada por objetos memoizados ou por uma relation antiga.

Manter os contratos de POST/PATCH e as revisões esperadas. Adicionar à
construção do serviço pelo controller um callback de reautorização, antes
de ler os parâmetros e novamente após os locks dos pais. Recarregar conta e
vínculo, construir uma política e um AccessScope novos e conferir o registro
persistido no escopo atual. Retornar o escopo fresco ao serviço para a nova
validação de pais e dos parâmetros, sem usar parâmetros como concessão.

Callbacks não fazem concessões, não alteram configuração nem executam PABX.
Uma recusa deve fazer rollback e não registrar falso sucesso na auditoria.
Chamadores internos já existentes conservam a assinatura compatível; as
entradas HTTP do Call Center obrigatoriamente fornecem o callback.

Prova necessária: HTTP real/PostgreSQL sintético com revogação de perfil ou
de elegibilidade enquanto PATCH espera o lock de unidade/fila; resposta
negada, configuração e trilha de auditoria preservadas. Preservar os seis
cenários concorrentes existentes e a homologação Chrome já aprovada.

Esta decisão não afirma serialização global dos demais módulos nem altera
o contrato das coberturas corporativas compartilhadas. Implementação e duas provas HTTP concorrentes preparadas; validação nativa pendente.


## Política global de pós-atendimento

O endpoint ACW tinha autorização anterior à espera do lock da conta. Aplicar
a mesma AuthorityTransaction, com membro recarregado e autorização dentro
do lock antes de persistir. Uma política que afeta a conta inteira exige
cobertura GROUP quando a estrutura corporativa está configurada; cobertura
de unidade não autoriza escrita global. Sem estrutura configurada, manter
o contrato anterior de configurar CC. A leitura continua autorizada pela
permissão nativa. Nenhum perfil, valor operacional ou cobertura é concedido.

A capability configuration_global vem do servidor e controla o botão; APIs
manipuladas continuam negadas. Três cenários API comprovam unidade/GROUP e permissão funcional,
um Vue verifica o controle, e dois cenários HTTP concorrentes aguardam
o bloqueio real observado em pg_stat_activity antes de liberar o lock.
Usar somente o banco sintético explicitamente conferido; nenhuma corrida
em produção. Ampliar o Chrome existente de limite corporativo sem remover
as suas asserções. Todos esses casos exigem a próxima CI nativa.
