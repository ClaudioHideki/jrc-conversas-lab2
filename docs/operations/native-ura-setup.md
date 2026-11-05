# Configuração da URA nativa no Broker e no JRC Conversas

Este procedimento usa a imagem padrão do Grupo JRC deste repositório e o executor nativo do Broker. Cada cliente recebe a mesma capacidade de software, mas tem sua própria empresa, conta, caixa, credenciais, agentes e versão do fluxo. O JSON da OIA é uma referência de comportamento; importar um export do Typebot diretamente como se fosse um Flow nativo não converte integrações nem comprova paridade.

GoPure e outras instalações de clientes não fazem parte desta atualização. Alterar o padrão LAB2 não atualiza automaticamente os contêineres de outras empresas. A imagem deve ser selecionada e implantada explicitamente em cada serviço autorizado.

## Responsabilidades

| Componente | Responsabilidade |
| --- | --- |
| Broker | WhatsApp, sessão do canal, empresa, validação e publicação do Flow, menus, estado de execução, expediente, transferência e controle de posse bot/humano. |
| JRC Conversas | Conta, caixa API, agentes/equipes, conversa humana, mensagens públicas, pesquisa CSAT e integração nativa autorizada. |
| Imagem padrão LAB2 | Código genérico e editor congelado compatível; nenhuma chave, conta de cliente, sessão de WhatsApp ou decisão de roteamento embutida. |

## Preparar a imagem e a instalação

1. Partir da revisão padrão atual aprovada, preservando os módulos existentes. Publicar pelo workflow `build-ghcr.yml`, com SHA completo, `component=app`, `backoffice_candidate=true` e o identificador de uma execução bem-sucedida de `backoffice-flow.yml` no mesmo SHA e branch. Para publicar, informar `publish=true`. O namespace é derivado do próprio repositório. Tags SHA existentes não devem ser sobrescritas.
2. Registrar o digest imutável, a revisão OCI e `/app/.git_sha`. Rails, Sidekiq e o serviço de preparação do banco devem usar a mesma imagem. Uma execução verde de CI não comprova implantação.
3. Aplicar o perfil `deploy/jrc/native-ura.env.example`, substituindo os domínios. Nunca copiar um ambiente completo de outro cliente. Preservar `SECRET_KEY_BASE`, banco, Redis, armazenamento e chaves já configuradas.
4. Criar `JRC_BROKER_CREDENTIAL_KEY` apenas se ainda não existir. Ela tem 32 bytes em base64 e protege o token do módulo Broker. As credenciais do Flow usam uma derivação de `SECRET_KEY_BASE`; não exigem uma chave adicional inventada para o Flow.
5. Executar a preparação de banco prevista pelo Compose e confirmar Rails e Sidekiq saudáveis. `APP_TIME_ZONE` aceita identificadores IANA e mantém o armazenamento de datas em UTC; `TZ=UTC` mantém o relógio do sistema em UTC.
6. Disponibilizar os recursos `jrc_broker` e `jrc_flows` na conta pelo superadministrador, respeitando os opt-outs existentes. Novas instalações recebem esses módulos como disponíveis; isso não cria vínculos, credenciais, bots ou canais automaticamente. A habilitação global e a habilitação da conta são verificadas separadamente.

Na atualização de uma instalação existente, a migração de campanhas de e-mail pode constar com a versão antiga `20260904150000`. O mesmo DDL passou a usar `20261021090000` na base padrão. O atualizador reconhece o histórico antigo somente após conferir colunas, defaults, nulabilidade, seis índices válidos/prontos e a chave estrangeira validada. Nesse caso, o Rails registra a nova versão sem reescrever registros nem repetir o preenchimento de destinos. Uma estrutura incompatível interrompe o preparo com `JRC_CAMPAIGNS_LEGACY_SCHEMA_MISMATCH`; investigar a divergência em vez de apagar colunas ou editar `schema_migrations` manualmente.

## Configurar a empresa no Broker

1. Selecionar a empresa correta e confirmar seu direito de uso do Flow no plano administrativo. Uma empresa com Flow habilitado não habilita as outras empresas do serviço compartilhado.
2. Criar ou adotar o canal de WhatsApp da empresa, conectar o número autorizado e conferir o estado conectado. Não reutilizar sessões ou canais de produção para preencher dados ausentes da homologação.
3. Em Integrações, cadastrar o destino Chatwoot/JRC Conversas: origem HTTPS canônica, ID da conta e token de um administrador autorizado dessa conta. Salvar pelo campo protegido. Confirmar que a integração aponta para a conta correta antes de selecionar a caixa.
4. Criar ou adotar uma caixa API dessa conta e vinculá-la ao canal. Conferir os identificadores de canal, integração, conta e caixa. Nome de caixa semelhante não comprova vínculo correto.
5. Emitir a chave de controle da conta do módulo JRC, quando necessária para o painel de conexões, e salvá-la somente no campo protegido do JRC Conversas. Não colocá-la no Git, JSON do Flow, imagem, logs ou relatório.
6. Confirmar uma mensagem recebida e uma resposta pública antes de ativar automação. Esse teste comprova transporte; os testes de URA são separados.

## Preparar a caixa no JRC Conversas

1. Adicionar à caixa os agentes e equipes reais do cliente. Identificadores de agentes da empresa usada como exemplo não podem ser reutilizados em outra conta. Conferir participação, disponibilidade e permissão de atribuição.
2. Definir uma única fonte para cada saudação e aviso. Na homologação OIA, a saudação da caixa e a atribuição automática foram desligadas para que o Flow controle a entrada e o destino. Regras gerais, AgentBots e automações legadas devem ser revisados para evitar respostas e atribuições concorrentes.
3. Um vínculo AgentBot legado, inclusive inativo, impede adotar a combinação nativa sem AgentBot. Resolver o vínculo pela configuração suportada antes da ativação; não apagar associações no banco para contornar a validação.
4. No módulo Broker da conta, informar a origem aprovada, a empresa e a chave de controle da conta, salvar e conferir o estado. O token de API do Chatwoot e a chave de controle do módulo são credenciais diferentes.

## Criar e ativar o Flow

1. No Broker, criar um rascunho nativo ou importar um export no formato nativo compatível. Converter o comportamento de origem em menus, condições, mensagens, retorno, tratamento de opção inválida, expediente e transferências nativas. Não manter webhooks para Bot Bridge, Typebot ou Budibase como dependência operacional.
2. Configurar cada transferência usando o catálogo real do destino. Escolher integração, conta, caixa, equipe e agente, conforme o comportamento esperado; conferir as revisões de credencial e destino. O texto exibido no menu não determina o agente efetivamente atribuído.
3. Configurar idioma, horários, fuso, feriados, tentativas, inatividade e avisos conforme a política fornecida pelo cliente. Valores de homologação não representam configurações comprovadas da empresa original.
4. Validar o rascunho, corrigir todos os erros, publicar uma versão imutável e vincular essa versão somente ao canal autorizado. Salvar o ID do Flow, a versão e o vínculo ativo.
5. Conferir o modo da conversa antes do teste. Uma conversa já sob controle humano não deve reiniciar o bot automaticamente. Para uma conversa de teste, usar o controle explícito de retomar o bot/nova sessão. Não reproduzir mensagens antigas como se fossem novos eventos.
6. Após a seleção do atendente, conferir o resultado da transferência na execução do Broker e a atribuição efetiva no JRC Conversas. Enviar outra mensagem de teste e verificar que o bot permanece pausado durante o atendimento humano.

## Editor incorporado ao JRC Conversas

O executor no Broker e o editor incorporado são etapas distintas. É possível publicar e operar o fluxo no painel do Broker enquanto o registro do editor da conta ainda está pendente. A chave de controle do módulo Broker não substitui uma credencial Flow nem autoriza editar ou publicar fluxos.

O administrador da empresa no Broker precisa emitir uma credencial Flow com os escopos necessários (`flow:read`, `flow:edit`, `flow:publish`, `flow:bind`, `flow:executions:read`), aprovar o desafio de registro para as integrações exatas e emitir a autorização de instalação. No JRC Conversas, um administrador real da conta deve concluir as etapas em `/app/accounts/ID/flows/native`, usando os campos protegidos da credencial inicial, desafio do Broker e autorização de instalação. O contexto de origem, conta, integração e revisões deve ser validado nas duas pontas.

Os contratos administrativos atuais ficam em `apps/api/src/http/routes/flow-native.ts` no Broker. As operações autenticadas incluem `POST /v1/flow-delegations/native-credentials`, `POST /v1/flow-delegations/native-registration-challenges` e `POST /v1/flow-delegations/native-installation-grants`. Exigem sessão administrativa OWNER/ADMIN e revisões atuais. A emissão de credenciais pode exigir operação administrativa por API quando a interface não disponibilizar o emissor. Não extrair sessões do navegador, reutilizar token QR nem gravar credenciais diretamente no banco como substituto dessa autorização.

Sem concluir o registro e a autorização, não declarar o botão de abrir o editor incorporado funcional. Credenciais temporárias expiradas devem ser emitidas novamente pelo procedimento administrativo suportado.

## CSAT e encerramento

Configurar a pesquisa em Configurações da caixa → CSAT. Definir texto, escala e condição de envio conforme a política do cliente. Em uma caixa compartilhada de testes, limitar a pesquisa por etiqueta evita disparos em conversas não selecionadas. Encerrar somente a conversa autorizada e conferir convite, recebimento no WhatsApp, avaliação registrada e associação à conversa.

O convite nativo é uma mensagem `template/input_csat` sem remetente; o transporte Broker deve aceitá-lo sem abrir passagem para notas privadas ou outros templates. A geração do convite é idempotente e usa bloqueio transacional para evitar duplicação por reexecução. A existência desses testes não comprova uma avaliação real recebida.

## Aceitação de cada empresa

| Verificação | Evidência esperada |
| --- | --- |
| Transporte | Entrada e saída na caixa correta, recebimento no aparelho e ausência de duplicação. |
| Menus | Todos os idiomas, departamentos, opções, retorno e opção inválida com sequência observada. |
| Transferência | Execução confirmada no Broker, atribuição real no JRC Conversas e bot pausado após nova mensagem. |
| Expediente | Limites de horário e dias testados no fuso aprovado, com destino e aviso corretos. |
| Atendimento humano | Resposta pública entregue uma única vez, sem reinício ou reatribuição indevidos. |
| Encerramento e CSAT | Convite único, avaliação registrada, comportamento de reabertura e retomada aprovado. |
| Isolamento | Outra conta/caixa permanece fora do vínculo e das credenciais. |
| Imagem | Digest executando, SHA interno, Rails e Sidekiq saudáveis, configurações e dados preservados. |

Registrar testes locais, CI, inspeção da API, inspeção visual e confirmação física separadamente. Um percurso real não comprova todas as combinações. Não declarar paridade integral de OIA, CRF, Íris ou outro bot sem os exports, regras de negócio e evidências específicos.

## Diagnóstico

| Sintoma | Conferir primeiro |
| --- | --- |
| Mensagem chega, mas não entra na URA | Empresa e canal do vínculo ativo, versão publicada, modo bot/humano da conversa e execução correlacionada. |
| Menu rejeitado ou erro de ciclo | Compatibilidade da release do Broker com MenuV2, saídas e retorno; validar o rascunho antes de publicar. |
| Nome do menu não corresponde ao destinatário | ID real de agente/equipe, participação na caixa e catálogo de destinos; não inferir pelo texto do menu. |
| Saudação ou atribuição duplicada | Saudação da caixa, autoatribuição, AgentBot, regras de automação, reentregas e recibos dos efeitos. |
| Convite CSAT ausente | Condição/etiqueta da pesquisa, encerramento, mensagem template/input_csat e obrigação de entrega do Broker. |
| Editor não abre | Flags globais e da conta, origem permitida, credencial Flow, registro, autorização de instalação e validade/revisões. |
| Horário incorreto | APP_TIME_ZONE IANA no Rails e Sidekiq, regra do expediente do Flow e armazenamento UTC. |
| Coluna de campanhas já existe no preparo | Conferir a revisão da imagem e o histórico da migração de e-mail renomeada. A release atual verifica o legado antes de registrar a nova versão; não remover a coluna nem os dados. |
| Tela com marca de outra empresa | Repositório/digest implantado e configurações de marca da instalação; não corrigir isso alterando o repositório de outro cliente. |

Para rollback, usar o digest anterior registrado e o procedimento da release. Uma troca de imagem não desfaz migrations nem restaura credenciais. Desativar somente o vínculo de automação afetado quando necessário; preservar o transporte e o atendimento humano.
