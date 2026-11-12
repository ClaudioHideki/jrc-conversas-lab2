# DocuSign — checkpoint de desenvolvimento

Estado em 02/11/2026: **parcial**. Esta base ainda não substitui o fluxo contratual legado nem comprova homologação externa.

## Implementado

- Backoffice → Controle e gestão → Assinatura DocuSign, com credenciais e verificações em abas horizontais.
- Configuração por Account, administrada somente por administrador ativo com acesso ao CRM e cobertura de grupo quando a estrutura corporativa está configurada.
- Chave RSA e chaves HMAC criptografadas no servidor, vinculadas à conta, identificador interno e revisão. Segredos não são devolvidos pela API. Mudanças invalidam as verificações anteriores.
- Autenticação JWT da eSignature API usando as dependências Faraday, JWT e OpenSSL já existentes. O usuário e a conta retornados por UserInfo são conferidos; a URL base precisa pertencer ao ambiente DocuSign configurado.
- Adaptador para criar envelope, consultar envelope/destinatários, reenviar, solicitar cancelamento e obter PDF/certificado. O despacho durável já vincula o envio à versão exata e à conexão preservada. As demais ações operacionais pela tela e o consumidor de evidências finais continuam incompletos.
- `POST /webhooks/docusign/:integration_id`: verifica HMAC dos bytes originais, conta externa, identificador do envelope e formato do evento antes de persistir. O identificador da rota não substitui a autenticação HMAC.
- Recebimento durável e criptografado, deduplicado por integração/revisão/SHA-256. HTTP 202 significa apenas **notificação recebida**. O consumidor usa o vínculo exato de envio/conexão; recibos sem vínculo permanecem aguardando e não são associados ao padrão atual por aproximação.
- Fatos autenticados de cancelamento/recusa são refletidos no contrato nativo, com preservação do histórico. Conclusão informada permanece `completion_reported`, sem assinatura válida ou liberação de etapas. Os webhooks existentes foram preservados.
- Registro da auditoria com ator humano ou provedor, sem credenciais e sem payload contratual nos logs. O filtro integral do corpo do Connect é local a este controlador.
- Fronteira interna `Signatures::Gateway`, seleção de conexão somente na admissão e configuração técnica preservada por revisão. Detalhes, testes e limites em [separação do provedor](signature_provider_boundary.md).
- CPF protegido no Contato canônico, sem conferir poderes de representação. Cadastro, mesclagem, autorização e cache de permissões têm validação própria.
- O endpoint legado não confirma mais envio a partir de um ID digitado. As ações pela tela e a conferência das evidências finais continuam incompletas; o motor durável local não equivale a uma operação homologada para produção. Registros históricos e assinatura manual do cliente continuam separados da liberação operacional v2.
- Versões/PDF/hash imutáveis, snapshots de assinantes canônicos, propostas de poderes pela Central, admissão/despacho e reconciliação de envio incerto foram acrescentados em checkpoints locais. Consultar [admissão](signature_admission_checkpoint_20261102.json), [despacho e notificações](signature_dispatch_notifications_checkpoint_20261102.json) e [reconciliação](signature_reconciliation_checkpoint_20261102.json). Os respectivos testes usam HTTP/HMAC sintéticos.

## Configuração e homologação ainda necessárias

Não configurar esta implementação como uma integração contratual pronta em produção. Não houve deploy nem envio externo nesta etapa.

1. Preparar o ambiente DocuSign Developer/demo, integração e usuário com consentimento para `signature impersonation`. O responsável confirmou em 02/11/2026 que esse ambiente ainda não existe. Consultar o [roteiro de preparação](docusign_demo_setup.md).
2. Configurar a chave privada no campo próprio da aplicação, sem enviá-la pelo chat. As chaves de criptografia da aplicação precisam permanecer estáveis; sua rotação exige migração dos segredos armazenados.
3. Disponibilizar o ambiente de homologação em HTTPS público, mediante autorização de implantação. `FRONTEND_URL` deve indicar essa origem. Em localhost HTTP, a interface não apresenta uma URL de callback como pronta.
4. Configurar Connect em JSON SIM, com HMAC e apenas os eventos suportados. Não incluir PDFs no webhook: o corpo é limitado a 2 MiB, e os documentos finais deverão ser obtidos pela API autenticada.
5. Verificar OAuth pela ação explícita. Verificar recebimento a partir de um evento real da conta demo. Salvar credenciais não marca nenhuma verificação como concluída.
6. Depois de concluir as ações operacionais e a conferência de evidências finais, homologar um contrato sintético com múltiplos signatários, cancelamento, repetição e eventos atrasados. Testes com WebMock ou HMAC sintético não atendem a esta homologação.

## Pendências antes do envio contratual

- Concluir o caminho operacional de envio a partir da tela, reutilizando a admissão, as versões, os assinantes e os poderes aprovados existentes. Sem inferir autoridade de cargo, checkbox ou OCR.
- Concluir a consulta operacional de status/destinatários e as ações autorizadas de reenvio/lembrete/cancelamento pela conexão original. O histórico local não consulta o fornecedor.
- Obter e conferir documento final e certificado, todos os destinatários obrigatórios e eventuais assinaturas parciais. O consumidor de fatos já existente não realiza essa verificação nem registra uma assinatura válida.
- Homologar externamente a reconciliação já implementada. O adaptador não repete automaticamente uma escrita que sofreu timeout. O `transactionId` do provedor tem janela limitada; não é uma garantia de idempotência permanente.
- Habilitar o envio operacional somente com versão, assinantes, aprovações e tentativa durável. A antiga confirmação por ID digitado já foi removida; não é um substituto para concluir esse fluxo.
- Completar as ações e a visualização de evidências no painel contratual existente. Os bloqueios de implantação/provisionamento permanecem ativos sem assinatura verificada.
- Concluir os demais fluxos de política e decisão da Central; a aprovação de poderes já reutiliza o motor nativo, sem representar homologação jurídica ou externa.

## Fontes oficiais consultadas

- [Autenticação DocuSign](https://developers.docusign.com/platform/auth/)
- [DocuSign Connect](https://developers.docusign.com/platform/webhooks/connect/)
- [Modelo JSON SIM](https://developers.docusign.com/platform/webhooks/connect/json-sim-event-model/)
- [Verificação HMAC](https://www.docusign.com/blog/developers/manually-authenticating-hmac-signatures-docusign-connect-webhook-configurations)
- [Operações sobre envelopes](https://developers.docusign.com/docs/esign-rest-api/reference/envelopes/envelopes/update/)
- [Modelo oficial de envelope e transactionId](https://github.com/docusign/docusign-esign-ruby-client/blob/master/lib/docusign_esign/models/envelope_definition.rb)

As evidências de testes e as pendências dos quatro módulos são registradas na matriz de continuidade; esta nota não declara entrega integral do Word.
