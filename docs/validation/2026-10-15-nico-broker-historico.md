# Candidato NICO/Broker — histórico recente

Branch: codex/nico-broker-coordenado-20261015. Base JRC: b58e093dd3a32fe97829a4566660b83ee48b9eca.

## Comportamento

O NICO consulta as mensagens recentes da conversa autorizada em vez da janela antiga causada pela ordenação padrão de Message. Filtros de privacidade, limites e autorização foram preservados. O claim de turno delegado passa a selecionar a última entrada pendente conforme a estratégia de coalescência existente.

Mudanças: OperatorSession, ToolExecutor, ContextBuilder e CustomerTurnJob. Não houve alteração de modelo, provedor, orçamento, habilitação produtiva ou do código services/nico-runtime.

## Validação

No código original: 7 exemplos novos, 6 falhas reproduzindo a janela antiga/claim e 1 aprovação de isolamento. Após as seis correções: 80 exemplos aprovados em sete arquivos RSpec, sem falhas, com Rails e PostgreSQL reais num laboratório local isolado.

Foram cobertos Quick NICO, amostra de oportunidades, ferramenta read_conversation, contexto de análise, contexto delegado, claim de entrada, privacidade e Account, além das jornadas existentes de comandos, confirmação, notices e delegação comercial. Avisos de deprecação Rails/Rack/Ruby existentes foram registrados; não houve mudança de dependências para ocultá-los.

O CI dedicado executa esse perfil na branch candidata. Imagem e CI remotos só serão declarados aprovados após seus resultados efetivos.

## Componentes e servidor

Esta correção entra na imagem app do JRC, usada por Rails e Sidekiq. O runtime NICO instalado pode permanecer na revisão compatível porque seu código e contrato não foram alterados aqui. O namespace histórico de uma imagem não muda o repositório canônico do fonte.

Não instalar esse candidato em produção automaticamente. A futura homologação deve usar ambiente isolado, com conta/caixa de teste e revisão da compatibilidade com o Broker.

O programa completo continua incluindo coordenação bot/humano, ações e timeout Flow, módulos QR/Flow, multitenancy, canais, capacidade e piloto. Este incremento não encerra essas entregas.
