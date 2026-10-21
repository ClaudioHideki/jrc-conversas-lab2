# Candidato: Atendimento unificado e remetentes de campanhas

Bases preservadas: JRC `c03d96e477389fd1287e7365f29ccda6f3eaf009`; Broker `2e04b8f970dbbe9bee5d70b4368731177e7943e0`.
Este documento não confirma publicação, instalação nem envio real. Nenhuma configuração produtiva foi alterada nesta correção.

## Componentes que precisam de versão compatível

- JRC Rails e Sidekiq: a mesma nova imagem consolidada, preservando os comandos distintos de cada serviço.
- Broker API e messaging worker: a mesma nova imagem API com o contrato `chatwoot-campaigns/v1`.
- O frontend web do Broker e a imagem da Evolution não foram alterados por este delta.
- Não há migration nova nesta correção. Antes da promoção, conferir migrations pendentes da instalação existente com backup; não presumir que versões mais antigas já tenham recebido a consolidação anterior.
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
- A política atual do Broker permite esse envio automático externo apenas com executor **EXTERNAL** na caixa. Não trocar automaticamente o executor de uma caixa com Flow/Broker/NICO responsável. Se esse for o caso, revisar a operação antes da promoção. A aplicação apresenta a incompatibilidade e mantém o bloqueio.
- Não é necessário conceder acesso à API genérica de mensagens nem usar JWT de usuário em jobs. Os dois endpoints novos são somente leitura, com `chatwoot:read`, isolamento por organização, destino, Account, caixa, conversa e mensagem.
- Para arquivos, manter storage/downloads da central acessíveis pelos mecanismos autorizados já existentes do Broker. Arquivos importados são vinculados por Active Storage; URLs externas exigem o guard público SSRF. Não autorizar redes privadas para contornar falhas de mídia.

## As duas caixas observadas anteriormente

**WhatsApp JRC QR:** callback identificado como Broker. Precisa do vínculo e configuração de controle acima, além da nova API/worker. O digest API informado anteriormente (`4bf8b01…`) é da base `2e04b8f` e ainda não oferece o contrato novo.

**WhatsApp Demo:** callback identificado como Evolution direta, `/chatwoot/webhook/...`. É um transporte diferente. Para continuar direto, exige mapeamento explícito por Account/inbox em `JRC_CAMPAIGNS_EVOLUTION_CONNECTORS`, número/instância confirmados e chave referenciada por variável privada, conforme o adaptador já existente. A alternativa é uma migração planejada da conexão para o Broker. Não usar o adaptador direto da Evolution para enviar por uma caixa do Broker, pois isso contornaria sua autoridade e poderia duplicar mensagens.

## Fluxo de campanha e aceite posterior

Importar/sanitizar lista → registrar consentimentos aplicáveis → escolher lista/público → escolher caixa(s) remetente(s) e distribuição → configurar mensagens/janela/intervalo → revisar → aprovação humana → iniciar explicitamente.

Consentimento, blacklist, bloqueio do contato e isolamento permanecem obrigatórios. Template Meta continua exigindo caixa oficial; campanhas Broker, Evolution direta e oficiais usam campanhas separadas. NICO permanece assistente da plataforma; não é requisito para despachar a campanha. Nenhum JARVIS/JEV é reativado por esta correção.

Um ID local significa enfileiramento, não envio pelo provedor. Apenas o recibo Broker derivado do estado real do transporte contabiliza envio/entrega/leitura e libera o próximo passo. Resultado incerto pausa e bloqueia reenvio automático; uma confirmação posterior pode reconciliar o registro sem repetir o envio.

Na homologação autorizada, testar um destinatário consentido por caixa, texto e arquivo, retorno à mesma conversa, nota privada não encaminhada, repetição da mesma solicitação sem duplicar, revogação, pausa e identidade divergente. Conferir **Todas** como administrador e **Minhas** com atribuição e acesso à caixa. PABX permanece desligado pela divergência tenant 8/accountcode 12.

Não realizar disparo real, alteração de executor, ativação de integração, migration em produção ou deploy apenas com base nos testes simulados.
