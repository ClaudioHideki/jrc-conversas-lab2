# DocuSign — checkpoint de desenvolvimento

Estado em 02/11/2026: **parcial**. Esta base ainda não substitui o fluxo contratual legado nem comprova homologação externa.

## Implementado

- Backoffice → Controle e gestão → Assinatura DocuSign, com credenciais e verificações em abas horizontais.
- Configuração por Account, administrada somente por administrador ativo com acesso ao CRM e cobertura de grupo quando a estrutura corporativa está configurada.
- Chave RSA e chaves HMAC criptografadas no servidor, vinculadas à conta, identificador interno e revisão. Segredos não são devolvidos pela API. Mudanças invalidam as verificações anteriores.
- Autenticação JWT da eSignature API usando as dependências Faraday, JWT e OpenSSL já existentes. O usuário e a conta retornados por UserInfo são conferidos; a URL base precisa pertencer ao ambiente DocuSign configurado.
- Adaptador para criar envelope, consultar envelope/destinatários, reenviar, solicitar cancelamento e obter PDF/certificado. **O adaptador ainda não está ligado ao contrato e suas versões.**
- `POST /webhooks/docusign/:integration_id`: verifica HMAC dos bytes originais, conta externa, identificador do envelope e formato do evento antes de persistir. O identificador da rota não substitui a autenticação HMAC.
- Recebimento durável e criptografado, deduplicado por integração/revisão/SHA-256. HTTP 202 significa apenas **notificação recebida**. O estado permanece `received`; o consumidor contratual ainda está pendente.
- Eventos não alteram contratos, assinaturas, etapas ou liberações. Os webhooks existentes foram preservados.
- Registro da auditoria com ator humano ou provedor, sem credenciais e sem payload contratual nos logs. O filtro integral do corpo do Connect é local a este controlador.

## Configuração e homologação ainda necessárias

Não configurar esta implementação como uma integração contratual pronta em produção. Não houve deploy nem envio externo nesta etapa.

1. Preparar ou confirmar o ambiente DocuSign Developer/demo, integração e usuário com consentimento para `signature impersonation`.
2. Configurar a chave privada no campo próprio da aplicação, sem enviá-la pelo chat. As chaves de criptografia da aplicação precisam permanecer estáveis; sua rotação exige migração dos segredos armazenados.
3. Disponibilizar o ambiente de homologação em HTTPS público, mediante autorização de implantação. `FRONTEND_URL` deve indicar essa origem. Em localhost HTTP, a interface não apresenta uma URL de callback como pronta.
4. Configurar Connect em JSON SIM, com HMAC e apenas os eventos suportados. Não incluir PDFs no webhook: o corpo é limitado a 2 MiB, e os documentos finais deverão ser obtidos pela API autenticada.
5. Verificar OAuth pela ação explícita. Verificar recebimento a partir de um evento real da conta demo. Salvar credenciais não marca nenhuma verificação como concluída.
6. Depois de concluir o consumidor contratual, homologar um contrato sintético com múltiplos signatários, cancelamento, repetição e eventos atrasados. Testes com WebMock ou HMAC sintético não atendem a esta homologação.

## Pendências antes do envio contratual

- Versões imutáveis do contrato/PDF e snapshots dos assinantes vinculados ao Contato do Cadastro Mestre.
- Validação de poderes de assinatura com evidências e política, sem inferir autoridade de cargo, checkbox ou OCR.
- Envelope e tentativa de envio persistidos antes do I/O, vinculados à versão e à revisão da integração.
- Reconciliação de resultados incertos. O adaptador não repete automaticamente uma escrita que sofreu timeout. O `transactionId` do provedor tem janela limitada; não é uma garantia de idempotência permanente.
- Consumidor autenticado de notificações, verificação dos destinatários, documento final e certificado, tratamento de assinatura parcial e proteção contra eventos de versões canceladas/substituídas.
- Substituição do endpoint legado que aceita ID externo informado manualmente e grava `sent`. Esse comportamento legado ainda existe e não deve ser confundido com envio pela DocuSign.
- Painel contratual dentro da solicitação, ações de assinatura e bloqueios de implantação/provisionamento vinculados à versão e às evidências válidas.
- Integração completa com as políticas e decisões da Central de Aprovações.

## Fontes oficiais consultadas

- [Autenticação DocuSign](https://developers.docusign.com/platform/auth/)
- [DocuSign Connect](https://developers.docusign.com/platform/webhooks/connect/)
- [Modelo JSON SIM](https://developers.docusign.com/platform/webhooks/connect/json-sim-event-model/)
- [Verificação HMAC](https://www.docusign.com/blog/developers/manually-authenticating-hmac-signatures-docusign-connect-webhook-configurations)
- [Operações sobre envelopes](https://developers.docusign.com/docs/esign-rest-api/reference/envelopes/envelopes/update/)
- [Modelo oficial de envelope e transactionId](https://github.com/docusign/docusign-esign-ruby-client/blob/master/lib/docusign_esign/models/envelope_definition.rb)

As evidências de testes e as pendências dos quatro módulos são registradas na matriz de continuidade; esta nota não declara entrega integral do Word.
