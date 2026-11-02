# Preparação da homologação DocuSign

Confirmado pelo responsável em 02/11/2026: **a conta Developer/demo, a integração e o Connect ainda precisam ser preparados**. Este roteiro não cria uma conta, não publica um ambiente e não envia envelopes. O fluxo contratual continua parcial; consultar também [estado da implementação](docusign_integration.md).

## O que preparar na DocuSign

1. Criar uma conta [DocuSign Developer](https://developers.docusign.com/platform/account/) pertencente à organização e confirmar o acesso ao ambiente demo. Não usar a conta de produção nem contatos de clientes nos testes.
2. Criar uma integração de eSignature e mantê-la em **Demo**. A DocuSign documenta tanto Apps and Keys para integrações demo quanto a [Developer Console](https://developers.docusign.com/platform/create-ik-developer-console/), atualmente descrita como beta. Usar a interface disponível na conta; este projeto não depende de migrar ou promover uma integração para produção.
3. Anotar separadamente o Integration Key/Client ID, o User ID GUID do usuário remetente e o API Account ID GUID da conta demo. São identificadores diferentes. O conector confere usuário e conta via UserInfo; não escolhe automaticamente a primeira conta disponível.
4. Configurar um par RSA de pelo menos 2048 bits na integração, conforme o [JWT Grant](https://developers.docusign.com/platform/auth/jwt-get-token/). Manter a chave privada no gestor de segredos da organização e depois inseri-la no campo protegido do JRC. A chave pública fica na DocuSign. Não colar chaves no chat, em tickets, documentos do cliente ou no Git.
5. Conceder consentimento ao usuário remetente para os escopos `signature impersonation`, seguindo o fluxo oficial aplicável à conta. Registrar uma redirect URI controlada pela organização quando o consentimento escolhido exigir esse cadastro. O JRC atual usa JWT; não existe um callback de Authorization Code implementado nesta etapa e não se deve inventar uma rota para isso.

## O que preparar no JRC de homologação

Esta parte depende de uma implantação de homologação **autorizada separadamente**. Não reutilizar o domínio, banco, Redis ou volumes de produção.

- HTTPS público com certificado válido, origem definida em `FRONTEND_URL` e encaminhamento do POST do Connect ao Rails sem alterar o corpo ou remover seus cabeçalhos de assinatura.
- Rails e Sidekiq com o mesmo código e configuração de criptografia estável. Perder ou trocar essas chaves sem um plano de rotação impede ler os segredos e identificadores já protegidos.
- PostgreSQL e ActiveStorage próprios de homologação, acessíveis somente pelos processos necessários. As migrations devem ser revisadas e aplicadas nesse banco, nunca em produção durante esta tarefa.
- Saída HTTPS para autenticação e eSignature demo. O conector utiliza `account-d.docusign.com` e valida a origem eSignature retornada pela DocuSign; não aceita uma URL arbitrária informada pelo operador.
- Logs sem Authorization, CPF, chave RSA, HMAC ou corpo integral dos eventos. Dados e destinatários de homologação devem ser sintéticos e as caixas postais precisam pertencer à equipe que aceitou participar do teste.

Em **Backoffice → Controle e gestão → Assinatura DocuSign**, um administrador autorizado deve selecionar Demo e preencher os três GUIDs, a chave privada e as chaves HMAC. A cobertura corporativa de grupo continua necessária quando configurada. Salvar credenciais não verifica OAuth nem assinatura. Mudanças de configuração invalidam as verificações anteriores.

## Preparar o Connect

1. No ambiente demo, criar uma configuração personalizada de Connect para o usuário remetente de teste. Usar o formato **JSON SIM**, habilitar HMAC e a confirmação de recebimento. Consultar [configuração e evento de teste](https://developers.docusign.com/platform/webhooks/connect/create-configuration-trigger-event/) e [formato SIM](https://developers.docusign.com/platform/webhooks/connect/json-sim-event-model/).
2. Usar exatamente a URL exibida pelo JRC após a configuração e a definição da origem HTTPS. A rota real é `/webhooks/docusign/:integration_id`; esse parâmetro identifica a conexão preservada, é público e não dispensa HMAC. Cada nova revisão tem uma URL própria. Manter o perfil Connect e a URL anteriores enquanto houver assinaturas em andamento; não redirecionar o perfil antigo ao padrão novo. Conferir os perfis disponíveis na conta demo antes da rotação. Não usar o webhook de WhatsApp ou acrescentar um sufixo a outra integração.
3. Selecionar somente eventos já aceitos pelo código: `envelope-sent`, `envelope-delivered`, `envelope-completed`, `envelope-declined`, `envelope-voided`, `recipient-sent`, `recipient-delivered`, `recipient-completed` e `recipient-declined`. Outros eventos não estão implementados nesta base.
4. Não incluir documentos, certificados ou dados adicionais desnecessários no corpo. O receptor limita o corpo a 2 MiB. PDF e certificado deverão ser consultados pela API autenticada pelo consumidor contratual, ainda pendente.
5. Guardar a chave HMAC gerada na DocuSign e cadastrá-la no campo protegido do JRC. O código confere os bytes originais do corpo, a conta externa e o identificador do envelope antes de registrar a notificação.

A conexão exige duas verificações diferentes: a ação **Verificar autorização** precisa concluir JWT/UserInfo; um evento real e autenticado da conta demo precisa chegar ao Connect. Para esse primeiro evento pode ser necessário um envelope sintético criado diretamente no ambiente demo, pois o JRC não permite envio antes da verificação do Connect. Preparar o cenário com um destinatário da equipe; este roteiro não autoriza dispará-lo automaticamente.

O receptor confirma a persistência antes de responder. O objetivo operacional da DocuSign é receber a resposta em até cinco segundos, conforme sua [documentação de implementação](https://developers.docusign.com/platform/webhooks/connect/implement/). A confirmação HTTP e a indicação de Connect verificado **não significam contrato assinado**. Nesta base, os eventos permanecem na caixa de entrada, sem consumidor que conclua a assinatura.

## Critérios para declarar homologação externa

Somente depois de implementar e validar o vínculo contrato → versão → envelope → destinatários → evidências:

| Cenário | Evidência exigida |
| --- | --- |
| Autorização | OAuth real e UserInfo correspondente ao usuário e à conta demo configurados |
| Envio | Confirmação real da DocuSign vinculada ao SHA do PDF, à versão e aos destinatários; job agendado não basta |
| Assinatura conjunta | Estado parcial após o primeiro signatário e liberação somente após todos os obrigatórios |
| Conclusão | Destinatários confirmados, PDF final e certificado obtidos pela API, com hashes preservados |
| Repetição e atraso | Reenvio do mesmo evento não duplica efeitos; evento de versão anterior/cancelada não libera a atual |
| Incerteza e cancelamento | Timeout não gera outro envelope automaticamente; cancelamento é confirmado pelo provedor |
| Bloqueios | Aprovação obrigatória, poderes sem evidência ou contrato não assinado impedem as ações correspondentes |
| Isolamento | Conta e operadora/unidade diferentes continuam negadas no servidor, inclusive downloads |

Registrar data, ambiente, SHA do código, cenários e resultados sem segredos, CPF ou documentos completos no relatório. Testes locais com WebMock, HMAC sintético, uma rota HTTP 200/202 ou uma configuração salva não atendem a esses critérios.

## Situação atual

- Conta demo e integração externas: **não criadas nesta tarefa**.
- Configuração e adaptador locais: implementados e testados com dados sintéticos; sem credenciais reais.
- CPF do assinante: extensão protegida do Contato canônico, sem conferir poderes de representação.
- Versões contratuais, vários assinantes, prova de poderes e consumidor das notificações: **pendentes**.
- Implantação pública e primeiro envio de homologação: **não executados**.

Nenhuma alteração de Compose, publicação de imagem ou acesso a produção é necessária para revisar este roteiro e continuar a implementação local.
