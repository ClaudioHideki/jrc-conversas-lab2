# URA nativa na imagem padrão JRC Conversas

## Decisão do usuário

O repositório `ClaudioHideki/jrc-conversas-lab2` é a base padrão para Grupo JRC e novas instalações de clientes. A homologação deve usar uma imagem desse repositório com as atualizações válidas preservadas. O recurso de URA deve estar disponível na base padrão e o procedimento de configuração deve ser documentado. Correção explícita de escopo em04/11: alterar somente LAB/GrupoJRC e Broker de produção; não alterar imagem/repositório GoPure nem outros clientes.

## Base e responsabilidades

Base escolhida: `e7dba8149be63708dc1b9e38ab9479ec7cca2ffe`, branch `codex/whatsapp-connections-word-20261104`, compilação aprovada `41908753330`. Ela inclui `main` e as melhorias recentes de conexões, disponibilidade e onboarding. O checkout separado evita modificar as branches anteriores.

Broker executa o grafo, mantém versão/vínculo/estado, recebe WhatsApp e coordena transferência. Conversas fornece conta, caixa, agentes, histórico, atendimento, pesquisa CSAT e os módulos nativos. Cada cliente mantém origem, credenciais, agentes, horários e fluxo próprios. O export OIA é exemplo configurado apenas na empresa de homologação.

## Abordagens

Transportar os ajustes genéricos validados sobre o LAB2 atual preserva suas atualizações e sua identidade visual; esse é o caminho solicitado. Substituir o LAB2 pela árvore comercial anterior traria personalizações de outro produto e perderia melhorias do LAB2. Refazer a URA com um motor externo contrariaria a arquitetura já validada.

## Conteúdo da imagem

Incluir transporte CSAT sem classificá-lo como resposta humana, idempotência da pesquisa, rejeição de outro AgentBot na caixa nativa, fuso IANA configurável com banco em UTC, editor do Broker versionado e manifests verificáveis. Disponibilizar Broker/Flows para novas contas sem criar integração, credencial, vínculo, canal, agente ou fluxo automaticamente. Um opt-out explícito continua valendo. A imagem não contém dados nem segredos da OIA/HML.

Configuração por instalação inclui origem pública e chave de criptografia exclusiva; configuração por empresa inclui conta, caixa, membros e credenciais limitadas. A credencial de controle WhatsApp e a credencial de edição Flow são distintas. O registro nativo do editor e a aprovação da origem devem continuar sendo verificados.

## Entrega e limites

Publicar imagens por SHA, implantar somente no LAB autorizado, conservar banco/Redis/chaves e produzir um relatório completo com os passos reais. A imagem principal GrupoJRC será a base para futuras imagens de clientes; esta entrega não modifica os seus repositórios. O Broker compartilhado de produção está incluído e sua atualização já foi autorizada e executada. Nenhuma implantação da central GrupoJRC em produção está presumida pela publicação da imagem.

Os 26 percursos já passaram no motor local e no CI com provedores sintéticos. O teste físico atual comprova português, retorno, um encaminhamento a HML1, pausa e resposta humana recebida uma vez. Inglês, inválido, CSAT e os demais encaminhamentos físicos continuam exigindo suas evidências. Não declarar paridade integral de outros bots.
