# Fronteira entre o fluxo JRC e o provedor de assinatura

Complemento de 02/11/2026: manter DocuSign como único conector instalado, sem transformar o Backoffice em uma plataforma de fornecedores. A separação técnica abaixo está implementada. Os incrementos posteriores acrescentaram versões imutáveis, snapshots de vários assinantes, propostas de poderes com aprovação nativa e registro durável de intenção/despacho. **O fluxo contratual ponta a ponta permanece parcial**: faltam ações operacionais pela tela, obtenção e conferência das evidências finais e homologação externa. Nenhum teste simulado comprova poderes jurídicos ou uma assinatura real. A interface não habilita um envio incompleto nem usa um ID digitado como confirmação.

## Responsabilidades implementadas

| Parte | Arquivos | Responsabilidade |
| --- | --- | --- |
| Fluxo comercial | `app/models/jrc_crm/contract.rb`, `app/services/jrc_backoffice/contract_release.rb`, `app/services/jrc_approvals/commercial_gate.rb` | Contrato, permissões e bloqueios continuam no JRC; não usam classes ou estados DocuSign. Aprovação e conclusão da assinatura continuam distintas. |
| Fronteira interna | `app/services/jrc_backoffice/signatures/gateway.rb`, `provider_error.rb` | Operações de assinatura e erros comuns. Seleção fechada do único adaptador instalado, sem registro dinâmico, código do usuário ou fornecedor alternativo. A conta precisa continuar ativa e com CRM habilitado. Isso não substitui a autorização do contrato pelo chamador. |
| Seleção na admissão | `app/services/jrc_backoffice/signatures/connection_selection.rb` | Consulta o padrão somente ao admitir um novo envio. O trabalho já admitido deve manter a conexão selecionada, inclusive enquanto estiver na fila. |
| Conector DocuSign | `app/services/jrc_backoffice/docusign/adapter.rb`, `client.rb`, `credentials.rb`, `oauth_session.rb`, `transport.rb`, `connect_inbox.rb`, `connect_verifier.rb` | Credenciais, OAuth, endpoints, formato do documento/destinatários, estados relatados, reenvio/lembrete, cancelamento, PDFs e autenticação de eventos. |
| Padrão para novos envios | `app/services/jrc_backoffice/signature_configuration.rb`, `app/models/jrc_backoffice/signature_integration.rb` | Administração autorizada da configuração atual. Salvar uma revisão cria um novo snapshot técnico e invalida verificações do novo padrão. |
| Conexão preservada | `app/models/jrc_backoffice/signature_connection.rb` | Provedor, ambiente, conta externa, usuário/chave de integração, credenciais criptografadas, revisão e callback fixos. Alterar o padrão não reescreve esse registro. |
| Caixa de entrada | `app/models/jrc_backoffice/signature_notification.rb` | Evento durável, criptografado e ligado à conexão exata. `received` não significa assinatura concluída. Os dados brutos do provedor não são um DTO público. |

A migração `20261102040000` adiciona as conexões, FKs compostas por conta e uma trava no banco contra alteração/exclusão de sua configuração. Os horários de verificação podem ser registrados sem reescrever a configuração preservada.

O prefixo criptográfico legado `docusign:...` é mantido para conseguir abrir os segredos/eventos existentes. Trata-se de compatibilidade de criptografia, não de uma condição de negócio do contrato. O snapshot guarda o contexto necessário para decifrar suas próprias credenciais, sem recorrer às credenciais do padrão atual.

## Estados e capacidades

O adaptador recebe operações comuns e traduz para a eSignature API. Não recebe um JSON arbitrário de envelope vindo da interface operacional. O `transaction_id` continua obrigatório e um envio com resultado incerto não é repetido automaticamente.

Para o único conector instalado, as capacidades são envio, consulta, destinatários, reenvio/lembrete, cancelamento, documento final e certificado. O lembrete imediato usa a mesma operação real de reenvio suportada pelo cliente DocuSign; não existe um agendador de lembretes implementado nesta etapa.

No conector, reenvio e cancelamento retornam a aceitação da requisição pelo endpoint autenticado. Esse retorno não muda um estado de negócio do JRC. O consumidor de eventos já preserva conclusão informada, recusa e cancelamento autenticados; as ações operacionais correspondentes pela tela continuam pendentes.

O estado DocuSign `completed` é traduzido para **`completion_reported`**, não para `signed`. O domínio ainda precisará conferir versão, destinatários obrigatórios, PDF final e certificado antes de registrar uma assinatura válida. Estados desconhecidos retornam `unknown`; não são tratados como sucesso.

## Configuração atual e histórico

- Cada revisão recebe uma conexão e uma URL de callback próprias. A primeira conexão preserva a URL já configurada para compatibilidade. Revisões posteriores usam outro identificador público.
- Na homologação, manter a configuração Connect e a URL da conexão anterior enquanto houver assinaturas em andamento. Substituir a URL do perfil antigo pela nova não preserva a entrega de eventos históricos. A quantidade e a administração dos perfis disponíveis na conta demo precisam ser conferidas antes de usar rotação de conexão; este incremento não cria nem altera perfis na DocuSign.
- Consultar, reenviar, cancelar ou obter evidências de um envio existente deverá resolver sua conexão gravada. Não procurar novamente a configuração padrão da conta.
- O gateway recarrega a conexão preservada; edições ainda não salvas no objeto não mudam o ambiente usado.
- A seleção de uma nova admissão não recorre à conexão antiga caso a configuração nova ainda não esteja pronta. Depois da admissão, o gateway recebe a conexão gravada: uma mudança de padrão durante a fila não deve trocar nem invalidar o destino do trabalho já admitido. A consulta/reenvio histórico também mantém provedor, conta e ambiente originais.
- Um evento autenticado na conexão anterior fica ligado a ela e não verifica a conexão nova. A revogação do módulo CRM da conta continua bloqueando o recebimento e as chamadas pelo gateway.
- Desabilitar o padrão para novos envios não equivale a revogar as conexões históricas. Incidentes com credenciais antigas exigem revogação na origem e um procedimento explícito de suspensão; não foi acrescentada uma central de administração de múltiplos provedores.

A migração recupera apenas a revisão que ainda existe na configuração e associa os eventos da mesma revisão. Se um evento antigo se refere a credenciais de uma revisão já sobrescrita antes deste trabalho, essas credenciais não podem ser reconstruídas. O evento é preservado, mas não se inventa uma conexão nem se o redireciona ao padrão atual.

Contratos legados com apenas `signature_external_id` também não ganham uma conexão ou versão presumida. Seu identificador continua visível como histórico. Não foi habilitada consulta, reenvio ou cancelamento desses registros usando a configuração atual; uma eventual vinculação terá de comprovar a conexão e a versão originais.

## Bloqueio do registro manual de um suposto envio

`ContractsController#send_for_signature` não grava mais `sent` por receber `external_id`. IDs históricos continuam legíveis. O endpoint retorna `VERSIONED_DELIVERY_REQUIRED`, sem criar auditoria de envio, enquanto o fluxo integrado não estiver concluído.

As telas CRM de contratos reutilizam `SignatureDeliveryNotice.vue`: o texto operacional é **Enviar para assinatura**; fornecedor e identificador histórico aparecem nos detalhes. O botão permanece bloqueado com explicação verdadeira. O registro manual de um PDF efetivamente assinado continua no fluxo legado e mantém suas validações; não foi convertido em assinatura DocuSign.

`JrcBackoffice::SignatureRelease` mantém a liberação v2 no domínio interno. Um registro de assinatura do cliente pode ser preservado enquanto a ativação e a liberação continuam pendentes. A marcação histórica `signed` não substitui a verificação de evidências; o mesmo bloqueio alcança avanço do Backoffice, status operacional do pedido e criação do projeto. Projetos históricos não são apagados por esse bloqueio. O evento de assinatura não avança automaticamente as etapas v2; o comportamento legado v1 permanece separado.

## Vínculo durável implementado e liberação ainda pendente

`Signatures::Admissions`, `DeliverySnapshot`, `Dispatch` e seu job preservam referências obrigatórias à conta, contrato, versão imutável, SHA do PDF, snapshots dos assinantes, poderes aprovados, provedor, conexão e ambiente. A intenção e a reserva do despacho precisam estar commitadas antes do I/O. Fila, resultado incerto e confirmação de envio são estados distintos; uma tentativa incerta não é reenviada automaticamente. A identificação externa só é vinculada após confirmação, inclusive na recuperação por transação original.

A seleção do padrão ocorre **somente na criação desse envio**. Depois disso, despacho, recuperação e eventos usam a conexão gravada. `Notifications` e seu job consomem os fatos autenticados sem transformar `completion_reported` em assinatura válida. O histórico operacional é somente de leitura. A obtenção e a verificação de evidências reais de todos os assinantes obrigatórios ainda precisam ser concluídas antes de liberar a versão atual, sem reativar versão cancelada/substituída nem completar a solicitação inteira. O verificador interno padrão continua recusando a liberação.

Os serviços chamadores usam `ContractAccess`, `AuthorityAccess` e `DispatchContext` para manter as políticas nativas, a cobertura de operadora/unidade e a revalidação do ator antes de cada operação. O gateway não recebe `account_id` ou `user_id` do navegador como autorização e não substitui essas políticas. Futuras ações operacionais precisam manter essas mesmas verificações.

Uma futura troca exigirá implementar outro adaptador com suas capacidades reais e adequar a configuração do fornecedor. Os contratos, aprovações, pendências e bloqueios do Backoffice continuarão consumindo a fronteira comum. Não há outro fornecedor implementado ou selecionável como integração funcional nesta entrega.

## Evidências automatizadas

Os checkpoints de [admissão](signature_admission_checkpoint_20261102.json), [despacho e notificações](signature_dispatch_notifications_checkpoint_20261102.json), [histórico](signature_history_ui_checkpoint_20261102.json) e [reconciliação](signature_reconciliation_checkpoint_20261102.json) registram os incrementos posteriores e os lotes efetivamente executados. Os testes do gateway abaixo continuam demonstrando a fronteira do conector; a durabilidade é validada pelos serviços/jobs adicionais, inclusive com commits e concorrência reais no PostgreSQL descartável.

- `spec/services/jrc_backoffice/signatures/gateway_spec.rb`: envio traduzido, status sem falso `signed`, falha incerta sem repetição, cancelamento/certificado, conta revogada, seleção de novas admissões, ambiente histórico e troca do padrão para um identificador não instalado sem redirecionar o envio antigo. O teste entre admissão e submissão conserva a conexão selecionada enquanto o padrão muda; simula o intervalo de uma fila, mas não implementa nem comprova um job durável de envio. O identificador não instalado é apenas uma prova de recusa, não um segundo conector.
- `spec/requests/webhooks/docusign_spec.rb`: HMAC, isolamento de contas, repetição, conexão desabilitada na criação, revisão histórica após mudança do padrão e impossibilidade de verificar a nova conexão com o evento antigo.
- `spec/services/jrc_backoffice/signature_connection_upgrade_spec.rb`: migração reversível, preservação de dados nativos e do ciphertext existente, associação dos eventos à revisão conhecida.
- `spec/requests/api/v1/accounts/crm/signature_delivery_guard_spec.rb`: ID digitado não fabrica envio, histórico preservado e acesso de outro usuário/conta negado.
- `spec/services/jrc_backoffice/signature_release_spec.rb` e a regressão existente `spec/requests/api/v1/accounts/jrc_approvals/commercial_api_spec.rb`: assinatura do cliente registrada separadamente, legado preservado e liberação operacional dependente de evidência verificada, sem referência a estados DocuSign.
- Regressões selecionadas de CRM, Backoffice, Cadastro Mestre, Central, Projetos e ownership continuam no gate desta etapa. O relatório de checkpoint informa os resultados efetivamente obtidos.

Todos os HTTPs de assinatura nessas suítes são simulados. Não houve criação de conta demo, consentimento real, contrato enviado, homologação externa, deploy ou publicação de imagem. O [roteiro de preparação demo](docusign_demo_setup.md) registra a dependência externa confirmada pelo responsável.
