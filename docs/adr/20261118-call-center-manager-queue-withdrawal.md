# Confirmação do gestor na retirada do último agente elegível

Status: incremento candidato; testes nativos e Chrome próprios ainda não executados.

## Decisão

O usuário definiu confirmação explícita do gestor, revisão e auditoria para a retirada do último agente elegível de uma fila ativa (figura 12). Não exigir aprovação formal na Central de Aprovações nem publicar alterações no PABX.

## Escopo técnico

Aplicar ao caminho nativo de atualização de QueueMembership. Reutilizar a permissão existente de configuração, o Account mutex, locks de fila/unidade/registro, revisão otimista, ModulePolicy, OrganizationalScope e a auditoria administrativa obrigatória. Nenhuma permissão nova ou automática.

Conferir elegibilidade configurada local: vínculo ativo de agente no período, fila/unidade ativas, permissão e elegibilidade atuais, usuário autenticável e cobertura corporativa. Não contar supervisor isolado ou usuário sem elegibilidade. Presença online, pausa atual e provider_pending não substituem essa conferência. Substituição válida por outro agente da mesma fila não é apresentada como fila vazia.

A primeira tentativa com impacto 1→0 não grava. Retornar o impacto autorizado e um recibo assinado de dez minutos, vinculado à conta, gestor, vínculo e versões anterior/proposta. Somente confirmação booleana literal com recibo correspondente permite prosseguir. Mudar o rascunho ou contexto invalida a confirmação; permissões e estado são conferidos de novo no servidor. O recibo nunca concede acesso.

Registrar a revisão na mesma auditoria nativa da alteração e na mesma transação. Guardar somente hash do recibo e metadados mínimos; o token é filtrado dos logs e não vai para armazenamento do navegador. Exibir confirmação também no histórico administrativo autorizado.

## Limites

Este incremento cobre retirada/reclassificação/mudança de vínculo pelo endpoint nativo de participantes de fila. A figura 12 permanece parcial: remoção indireta via equipe, hierarquias e supervisão principal ainda exigem avaliação própria no caminho nativo. Não bloquear revogações de segurança, desligamento de usuário ou acessos dos demais módulos com uma regra de confirmação inventada. Nenhuma integração externa é declarada homologada.

## Validação requerida

Rails: impacto, assinatura/expiração, confirmação literal, rascunho alterado, outro gestor/conta/unidade, perda de autoridade, substituição e não elegíveis. Provar com HTTP e fixtures commitadas que a perda de outro agente durante o lock é detectada e que falha do insert de auditoria desfaz a retirada. Vue: submissão real do popup, confirmação, invalidação e identidade. Chrome: quatro projetos desktop/mobile claro/escuro, 136 casos obrigatórios mantendo os 132 anteriores, persistência, negados, histórico e nenhum comando PABX.


## Revisão dos consumidores e QA pendentes deste candidato

O SupervisorSnapshot reutiliza AgentStateSnapshot#call. Para não herdar o catálogo privado de outro operador, os novos campos ficam exclusivamente em operator_payload, chamado apenas pelos endpoints autenticados do próprio operador e suas qualificações. O painel do supervisor mantém a projeção genérica; o motivo de evento ligado a fila não visível é ocultado, preservando sua visibilidade para o supervisor com cobertura adequada. Testes de APIs reais preparam operadores com cobertura A/B e supervisor restrito à A, além de perda posterior da unidade e tentativa de forjar o ID do operador. Execução nativa pendente.

Uma captura real de 5e12db0a mostrou connected no detalhe da perna da chamada. O candidato reutiliza o tradutor de estados já existente e mantém código/filas da API. Há regressão Vue e asserção adicional nos quatro cenários Chrome existentes, sem mudar comandos ou regras de telefonia. Execução pendente no próximo SHA.
