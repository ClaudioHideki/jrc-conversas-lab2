# Operação da versão consolidada

Esta entrega altera o aplicativo JRC Conversas (Rails/Vue), API/web e workers do Broker. O runtime independente NICO não mudou; sua imagem atual deve ser preservada. Publicação de imagens não altera o servidor e não ativa automações.

## Ordem de implantação futura

1. Guardar backup verificado do PostgreSQL, arquivos e configuração privada dos serviços. Registrar imagens atuais para retorno. Homologar em ambiente separado antes da troca de produção.
2. Instalar o aplicativo JRC candidato preservando a mesma configuração de banco, Redis, storage, domínios e runtime NICO. Aplicar as migrations pelo procedimento já adotado pelo serviço Rails. Esta candidata adiciona `20261019120000`, `20261019130000` e `20261019140000`. Verificar o estado das migrations e saúde de Rails/Sidekiq. Não recriar volumes ou substituir o schema por um dump local.
3. Confirmar o vínculo atual de empresa/conta/caixa/API actor na central. Histórico e comandos CRM exigem as novas capacidades do adaptador. Uma instalação externa sem esse adaptador permanece sem essas capacidades; mensagens normais usam seu contrato existente.
4. No Broker, usar API/web pelos digests do mesmo corte aprovado, código Compose da mesma revisão e todos os workers da mesma imagem API. O corte acrescenta migrations0066–0068 e o worker de histórico. Não combinar Compose novo com a imagem antiga.
5. Executar uma vez a migration no projeto Dokploy correto, a partir do checkout de implantação: `docker compose -p jrc-broker-broker-ophydn -f ./infra/dokploy/compose.yaml --profile maintenance run --rm migrate`. Depois usar o deploy completo normal. O campo Advanced Run Command deve permanecer vazio para a operação normal, evitando que novos deploys executem somente a migração.
6. Conferir readiness, versão/estrutura, workers e vínculos; depois realizar uma importação pequena e uma jornada sintética isolada, autorizadas explicitamente. Não vincular/ativar o bot de teste em caixas de uso geral.

Nenhum destes comandos foi executado no servidor durante o desenvolvimento desta entrega.

## Configuração e limites

- Histórico é opcional. `HISTORY_EVOLUTION_DATABASE_URL` deve usar uma credencial dedicada somente de leitura no banco do engine. A configuração por frota usa `HISTORY_EVOLUTION_DATABASES_JSON`; credenciais privadas ficam fora do Git. Os defaults do worker são intervalo5000ms e pool2. Grants mínimos e contrato estão no README do módulo de histórico do Broker.
- Sem a fonte verificada, não existe importação histórica. O contrato atual cobre texto individual em cache a partir da fronteira de identidade verificada. Não promete todo o histórico do telefone, grupos ou mídia.
- Importação preserva datas/direções e não dispara bot, saudação, notificação ou envio. Conclusão local e espelhamento na central têm resultados separados.
- A aba “Minhas” depende da atribuição de agente na central. Importar mensagens não transfere todas as conversas ao dono do telefone.
- Lotes exigem prévia e aprovação dos clientes exatos; cadências têm passos nativos finitos e param por resposta, intervenção ou cancelamento. Não são campanhas públicas.
- O nó `domain` suporta lead, tarefa e reunião CRM com responsável autorizado. Reunião é registro nativo, sem convite externo ou chamada. Diretório acima de200 responsáveis é recusado explicitamente, exigindo paginação futura.
- Voz NICO é modo interno opcional do operador, com revisão e limites de5min/12turnos. Não é mídia de chamada WhatsApp/SIP e não dispensa confirmação de alterações/envios públicos.
- Capacidade para500 empresas/10mil conexões, Meta, Chatwoot externo, áudio real e rollback operacional precisam de homologação própria. Os testes locais não certificam esses ambientes.

## Compatibilidade e retorno

As migrations são aditivas. Recibos e dados nativos não devem ser apagados para tentar retornar versões. A reversão da coluna de domínio recusa dados já existentes. O histórico usa uma fila separada `HISTORY_PENDING`, que o worker antigo de mensagens normais não consome. Um retorno real deve ser ensaiado com backup e as imagens exatas; o teste de migration local não substitui esse ensaio.
