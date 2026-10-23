# Registro automático das caixas do Broker no JRC

## Objetivo autorizado

Novas caixas criadas pelo Broker ou pelo módulo nativo do JRC devem ser
reconhecidas automaticamente na Account correta. O operador escolhe os
remetentes na campanha; não deve cadastrar uma autorização de caixa à parte.
Uma sessão desconectada não deve ser mostrada como pronta para enviar.

## Implementação

- Descoberta pela credencial de controle da Account, nunca por nome ou apenas
  pelo formato da URL. Validar organização, origem e revisão do destino.
- Registrar somente API inbox local, callback exato e IDs confirmados pelo
  endpoint de status. Não criar inbox, aprovar número, parear ou enviar mensagem.
- Comparar snapshot imutável da configuração antes de persistir cada vínculo,
  sob locks da integração, caixa e canal. Troca de credencial/destino ou callback
  durante HTTP impede persistência usando a autorização antiga.
- Hooks após commit de configuração, criação de inbox e alteração do callback;
  recuperação agendada a cada minuto para o caso de a caixa anteceder READY.
- Execução por administrador atual da Account, lock Redis com liberação pelo
  dono, lote de dez e continuação. Uma caixa defeituosa não impede as seguintes.
- Accounts suspensas não enfileiram nem executam a descoberta. Antes de salvar
  cada vínculo automático, aplicar novamente `JrcBrokerPolicy#manage?`, com a
  Account e o membership atual bloqueados. Suspensão, remoção ou rebaixamento
  do administrador durante HTTP impedem a gravação das caixas seguintes.
- Ordem dos locks: Account, membership, integração, inbox e canal. A ordem da
  Account antes da integração acompanha a configuração da credencial; nenhum
  GET ocorre dentro da transação local dos vínculos. Os caminhos manuais mantêm
  suas regras existentes.
- O catálogo remoto atual possui limite de 500 conexões. Paginação remota além
  desse limite é trabalho adicional, sem alegação de descoberta ilimitada.
- Mostrar o motivo conhecido da indisponibilidade na campanha; resposta de
  diagnóstico desconhecida recebe texto seguro, sem exibir conteúdo remoto.
- Preservar trabalhos e confirmações de campanhas; atualizar a lista nunca
  inicia um disparo.

## Evidências locais

- RED: caso de duas caixas sob troca de revisão reproduziu persistência usando
  a credencial substituída; corrigido com snapshot do Context desde a criação.
- GREEN: 16 cenários iniciais de sincronização, incluindo isolamento de Account,
  callback alterado, resposta ambígua, continuidade e duplicação de jobs.
- A rodada final anterior à revisão de autorização passou os 17 cenários,
  incluindo a inbox removida durante descoberta e o snapshot da credencial.
- RED da revisão: enfileiramento e execução para Account suspensa, suspensão
  durante status e remoção/rebaixamento do administrador reproduziram os
  comportamentos incorretos antes da correção.
- GREEN final: 23 cenários de sincronização, incluindo os 17 anteriores, cinco
  casos de suspensão/revogação e o controle de HTTP fora da transação local.
- Regressão ampliada inicial: 79 exemplos. A rodada final com serviços Broker,
  três contratos de requests, campanhas Broker/Evolution e webhook passou
  137 exemplos sem falhas no PostgreSQL/Redis isolados, com HTTP simulado.
- RuboCop dos sete arquivos Ruby da sincronização passou sem ofensas.
  Após a revisão, os três arquivos Ruby alterados foram novamente verificados,
  sem ofensas.
- Tela de campanhas: RED do motivo específico, seguido de 22 testes verdes em
  dois arquivos, com fallback seguro e preservação da revisão humana de envio.

## Estado de entrega

Fonte publicada na branch candidata separada do JRC, commit `a268bac3`.
O job frontend do CI39970029768 passou os568 arquivos e5.570 testes sem falhas
ou pendências. A seleção ampliada Rails executou305 exemplos e encontrou um
teste legado de consentimento com fixture de remetente inapto. O cenário foi
atualizado para verificar a restauração do público após nova autorização de um
destinatário anteriormente revogado, sem selecionar caixa nem iniciar campanha;
os14 exemplos focais passaram e o RuboCop do arquivo passou. A nova revisão
precisa repetir a regressão CI antes de gerar imagem/implantar.

Não importou clientes BemTeVi nem alterou reservas incertas de IA. A mudança
operacional autorizada do NICO foi o aumento do limite interno; os testes
completos do assistente continuam separados deste escopo.
