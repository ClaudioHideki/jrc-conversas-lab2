# Respostas rápidas e importação de rascunhos de aprovação

Data: 2026-11-15. Estado: implementação em validação; não constitui aceite produtivo.

## Decisão

Reutilizar CannedResponse, ActiveStorage, os drops Liquid nativos, ConversationPolicy, MessageBuilder, o editor e as permissões existentes. Um modelo admite um arquivo; o endpoint autenticado entrega seus bytes sem fornecer URL ou signed_id ao cliente. A inserção preserva um File no editor até o envio nativo. O envio direto exige uma confirmação distinta, confere conta/conversa/ator/revisão/janela e serializa a intenção sob lock da conversa; a chave e o digest ficam em Message.additional_attributes, JSONB nativo. Campos sem dados permanecem visíveis para preenchimento humano.

A sintaxe Liquid continua a mesma. Os aliases são substituídos após a avaliação para não executar dados do contato como código. Limites são locais ao renderer, sem alterar configurações globais. A empresa exige acesso ao Cadastro Mestre e cobertura corporativa. O catálogo original de respostas é da conta: não inventar uma nova ACL de unidade que o módulo não possui; a conversa continua submetida às políticas nativas de caixa/membership e ao overlay Enterprise.

Na Central, usar Dialog/PolicyEditor e os serviços Policies/Authorization/Ledger existentes. Catálogos JSON/CSV exigem escopo autorizado, dry-run e diff, confirmação e chave idempotente. Identidades são somente conciliadas por IDs existentes revisados; nenhum cargo, sugestão de nome ou importação concede poderes. Regras manuais/publicadas e versões anteriores são preservadas; só metadados gerenciados de rascunhos importados intactos podem ser atualizados. Conflitos abortam o lote e falhas intermediárias revertem a transação.

## Limites explícitos

Os 20 códigos do Word são avaliados, mas somente eventos nativos expressamente mapeados podem gerar Policy. Sem adaptador/mapeamento real, o item permanece pendente no relatório; não criar gatilhos fictícios. O arquivo fornecido não é executado contra bancos reais. Alçadas, aprovadores, prazo, substitutos e parâmetros de ativação continuam sujeitos à configuração e autorização próprias.

Instagram/TikTok exigem mensagens separadas de texto/mídia: o envio direto combinado é bloqueado; a revisão no editor mantém o fluxo nativo. WhatsApp continua limitado pela janela de atendimento, tipo/tamanho e configuração do canal. Produto/serviço usa somente o atributo contextual nativo `produto_servico` quando existente. Falha incerta de envio preserva conteúdo e intenção; o histórico/status nativos continuam sendo a autoridade sobre a entrega ao canal.

## Evidência exigida

RSpec com PostgreSQL/Redis descartáveis, concorrência independente, testes Vue, lint, migrations e gates pertinentes. Chrome com Rails/banco sintético, assets recém-compilados no GitHub, viewport 1440/390, preferências de tema persistidas, prévia/inserção/confirmação, contexto, anexos, configuração/importação e acessos negados. Resultados, SHAs, falhas e pendências registrados em relatório de controle; testes unitários não substituem o navegador. Nenhum build pesado no Windows, imagem Docker, publicação ou deploy é autorizado neste incremento.

Confirmação do usuário em 15/11/2026: manter o catálogo e os anexos compartilhados na conta, com as permissões nativas. Não foi autorizada uma nova partição por unidade dos modelos; cobertura corporativa e acesso à conversa continuam obrigatórios no contexto. O payload `catalog_import` é filtrado integralmente dos logs Rails. A geração do catálogo por escopo é independente da geração de leitura do arquivo/prévia, impedindo que um upload invalide a resposta autorizada do catálogo.

O atalho `/` do editor de atendimento abre a mesma prévia autorizada do botão inferior, incluindo o anexo; não insere silenciosamente apenas o texto de um modelo com arquivo. A opção é habilitada apenas no ReplyBox, mantendo o contrato de inserção legado dos demais contextos do editor. O dropdown descarta registros de outra conta presentes em cache. A conciliação opcional das 11 identidades é recolhida em seção expansível para deixar o diff legível no popup.

Cada envio direto de arquivo cria um anexo de mensagem próprio a partir do tempfile verificado do ActiveStorage, mantido aberto até o commit/upload nativo. Não reutilizar o blob do modelo em mensagens: um vínculo futuro da conversa com Service Desk deve proteger a cópia do chamado sem restringir o modelo compartilhado da conta. A autoridade da origem é conferida antes da leitura e novamente antes da criação da cópia.

A inserção revisada reutiliza o parser Markdown e a seleção do WootMessageEditor, preservando a formatação de modelos antigos. Quando o editor está ocupado por áudio/Copilot, inserir fica indisponível e o envio direto continua exigindo confirmação; falha de inserção remove somente o arquivo local dessa tentativa, mantendo o conteúdo para revisão.
