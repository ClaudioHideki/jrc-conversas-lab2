# Candidato: Atendimento unificado e remetentes de campanhas

Base JRC desta revisão: `abc1f7c57f55a7d9871101cd5b70c8b93becc7ca`. O Broker precisa da revisão compatível com a reserva canônica `chatwoot-campaigns/v1`, descrita abaixo.
Este documento não confirma publicação, instalação nem envio real. Nenhuma configuração produtiva foi alterada nesta correção.

## Componentes que precisam de versão compatível

- JRC Rails e Sidekiq: a mesma nova imagem consolidada, preservando os comandos distintos de cada serviço.
- Broker API e messaging worker: a mesma nova imagem API com o contrato `chatwoot-campaigns/v1`.
- O frontend web do Broker e a imagem da Evolution não foram alterados por este delta.
- Este delta não adiciona migration no JRC. O Broker precisa de `0072_chatwoot_campaign_intents.sql` e runtime compatível com baseline `0072`. Antes da promoção, conferir migrations pendentes de ambos os produtos com backup; não presumir que versões mais antigas já tenham recebido a consolidação anterior.
- O layout HOYA passa a ser o Atendimento padrão, inclusive para as entradas antigas `/dashboard` e `/conversations/:id`. Contextos antigos de caixa/etiqueta/filtro continuam disponíveis. O layout não habilita Call Center, PABX, alçadas ou operações de voz.

## Configuração necessária no JRC

Conferir a configuração existente, sem substituir chaves de criptografia:

1. `JRC_BROKER_ENABLED=true`, origem HTTPS exata da API em `JRC_BROKER_ALLOWED_ORIGINS`, `FRONTEND_URL` correto e `JRC_BROKER_CREDENTIAL_KEY` preservada. Rails e Sidekiq devem receber a mesma configuração.
2. Na Account correta, módulo Broker habilitado e integração configurada pela tela **Conectar seu WhatsApp**, com organização/destino correspondentes e credencial de controle com os escopos existentes. Não colocar credenciais no frontend nem no módulo Campanhas.
3. Adotar/vincular a conexão existente à caixa correta, conservando Account, inbox, integrationId e instanceId. Não criar caixa duplicada nem trocar apenas o webhook manualmente.
4. Conferir webhook assinado, conexão ativa e identidade do número confirmada. A seleção de campanha mostra nome da caixa e os últimos quatro dígitos fornecidos pelo Broker.
5. Em Campanhas, usar **Atualizar caixas e números remetentes** depois da configuração. Caixa identificada, porém sem vínculo/configuração/identidade, aparece indisponível com orientação; não é tratada como conectada.

## Configuração necessária no Broker

- API/worker com controle Chatwoot habilitado conforme a configuração existente (`CHATWOOT_CONTROL_ENABLED`), destino aprovado, Account/inbox corretas, credencial válida, callback verificado e identidade confirmada. Manter o worker de mensagens saudável: ele processa o webhook e os recibos reais.
- O envio desta integração usa **o transporte existente do Broker**, uma vez, através de `message_created` assinado. A mensagem conserva `campaign_id` e usuário legítimo; continua classificada como automação.
- A versão compatível reserva um intent canônico para a mensagem já gravada, antes do único callback assinado. O Broker valida ator, Account, caixa, conversa, mensagem, conteúdo e revisões; o fluxo não altera o executor da caixa. Saudação e atribuição automática incompatíveis mantêm o remetente indisponível e exigem configuração explícita.
- Não é necessário conceder acesso à API genérica de mensagens nem usar JWT de usuário em jobs. O controle usa `chatwoot:read` para prontidão/recibo e `chatwoot:manage` para reservar o intent. Credenciais ficam no servidor; cada operação é isolada por organização, destino, Account, caixa, conversa, mensagem e ator.
- Para arquivos, manter storage/downloads da central acessíveis pelos mecanismos autorizados já existentes do Broker. Arquivos importados são vinculados por Active Storage; URLs externas exigem o guard público SSRF. Não autorizar redes privadas para contornar falhas de mídia.

## As duas caixas observadas anteriormente

**WhatsApp JRC QR:** callback identificado como Broker. Precisa do vínculo e configuração de controle acima, além da nova API/worker. O digest API informado anteriormente (`4bf8b01…`) é da base `2e04b8f` e ainda não oferece o contrato novo.

**WhatsApp Demo:** callback identificado como Evolution direta, `/chatwoot/webhook/...`. É um transporte diferente. Para continuar direto, exige mapeamento explícito por Account/inbox em `JRC_CAMPAIGNS_EVOLUTION_CONNECTORS`, número/instância confirmados e chave referenciada por variável privada, conforme o adaptador já existente. A alternativa é uma migração planejada da conexão para o Broker. Não usar o adaptador direto da Evolution para enviar por uma caixa do Broker, pois isso contornaria sua autoridade e poderia duplicar mensagens.

## Fluxo de campanha e aceite posterior

Importar, colar ou selecionar contatos → escolher lista/público → escolher caixa(s) remetente(s) e distribuição → configurar mensagens/janela/intervalo → revisar → aprovação humana → iniciar explicitamente.

A lista selecionada alimenta o público sem exigir cadastro positivo extra de consentimento. Não se cria nem se altera evidência histórica para autorizar o envio. Blacklist, bloqueios, revogações registradas e isolamento continuam obrigatórios; opt-out de e-mail legado permanece preservado. Template Meta continua exigindo caixa oficial; campanhas Broker, Evolution direta e oficiais usam campanhas separadas. NICO permanece assistente da plataforma; não é requisito para despachar a campanha. Nenhum JARVIS/JEV é reativado por esta correção.

Um ID local significa enfileiramento, não envio pelo provedor. Apenas o recibo Broker derivado do estado real do transporte contabiliza envio/entrega/leitura e libera o próximo passo. Resultado incerto pausa e bloqueia reenvio automático; uma confirmação posterior pode reconciliar o registro sem repetir o envio.

Na homologação autorizada, testar um destinatário explicitamente selecionado por caixa, texto e arquivo, retorno à mesma conversa, nota privada não encaminhada, repetição da mesma solicitação sem duplicar, revogação, pausa e identidade divergente. Conferir **Todas** como administrador e **Minhas** com atribuição e acesso à caixa. PABX permanece desligado pela divergência tenant 8/accountcode 12.

Não realizar disparo real, alteração de executor, ativação de integração, migration em produção ou deploy apenas com base nos testes simulados.

## Reserva canônica e resultados incertos (delta de 22/10)

Depois do commit da mensagem nativa e antes de transmiti-la ao callback, o Sidekiq chama `POST /v1/integrations/chatwoot/control/connections/:integrationId/campaign-intents` com a chave estável `campaign:<deliveryId>` ou `test:<testDeliveryId>`. A reserva inclui os IDs canônicos de mensagem/conversa, campanha, tipo/texto e revisões de destino, identidade e responsabilidade. A chamada HTTP ocorre fora de locks/transações locais; a correlação `jrc_campaign_intent_id` é persistida em uma transação curta. O callback existente continua sendo o único transporte.

Timeout ou falha temporária repete somente a reserva/callback da mesma mensagem e chave; nenhum segundo registro de mensagem é criado. Uma reserva recusada suprime o callback. O intent do Broker expira em 24 horas e não é rearmado automaticamente. Mudança de vínculo, ator, identidade, revisão ou revogação exige reconciliação, sem criar nova mensagem para contornar o bloqueio. Testes anteriores pendentes ou desconhecidos impedem outra chave para o mesmo destinatário/caixa até a reconciliação. Teste individual continua exigindo início explícito e os controles operacionais do canal.