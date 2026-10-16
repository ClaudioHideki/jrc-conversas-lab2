# NICO: coordenação da caixa Broker legada

Corrigido o caminho de envio comum quando a caixa API aponta para o callback canônico da origem Broker configurada no mesmo Account, mas ainda não possui vínculo local. A prévia e a execução de uma aprovação anterior agora orientam a adoção administrativa existente. A URL nunca fornece autorização, credencial ou vínculo automático. Não há chamada HTTP nova sob lock.

Operação após instalar a candidata: administrador abre `/app/accounts/ACCOUNT_ID/whatsapp-connections`, confere a configuração do Account e escolhe **vincular caixa existente** na conexão correta. A adoção verifica o estado remoto READY, caixa e instância antes de salvar. Não recria a caixa nem inicia automação. Depois, o NICO apresenta prévia; confirmar solicita pausa coordenada e só registra a mensagem quando a pausa está confirmada. Isso não foi executado no servidor.

Evidência local: dois RED de bypass (prévia e aprovação anterior); GREEN de 20 exemplos do escopo de bindings, incluindo adoção real do serviço com respostas remotas sintéticas, envio único, nota privada, QR, registro nativo, credencial expirada e host/protocolo/porta diferentes. Os 20 exemplos de OperatorSession passaram na rodada anterior de integração do incremento. **18 exemplos de concorrência do commit gate passaram, sem pendências**, em banco PostgreSQL descartável e sem transporte real.

A primeira tentativa opt-in falhou na limpeza TRUNCATE das fixtures por statement_timeout de SQL de 14s do runner. Nenhuma falha de produto foi atribuída a esse resultado. A rodada isolada usou POSTGRES_STATEMENT_TIMEOUT=120s somente na sessão do banco de teste; limites e assertivas de concorrência permaneceram intactos. Duração: 14m43s. Nenhum ENV de aplicação/servidor ou teste foi afrouxado.

Revisão independente sem achados Critical/Important. RuboCop focal sem infrações após alinhamento. Limite: um executor externo sem registro e sem a rota canônica não pode ser descoberto pela caixa API; precisa do onboarding explícito. Não foi ativado bot, publicada imagem ou alterada produção.
