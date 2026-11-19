# ADR 0008: Abertura interna por destinatário da unidade

- Status: Aceita por solicitação do usuário
- Data: 2026-11-19

## Problema e escopo

O usuário informa que Ronald continua recebendo acesso negado e solicita a
correção no código, com escolha de qualquer agente da empresa. A consulta
administrativa confirmou vínculo ativo e as permissões nativas de um agente.
A sessão do Ronald e o endpoint exato que recusou o acesso não foram observados.

O código acoplava toda a projeção do módulo à validação da triagem legada,
limitava os destinatários à equipe dessa triagem e mantinha uma sessão negada
mesmo ao navegar para outra ação recém-autorizada pelo guard.

## Decisão

- A abertura interna oferece os destinatários ativos da unidade autorizada,
  independentemente da equipe da triagem. Conta, unidade, papel nativo,
  atribuição manual e restrições explícitas do destinatário continuam obrigatórios.
- Para a pessoa escolhida, usa a fila padrão se compatível; caso contrário,
  usa a fila/equipe explícita do destinatário ou atribuição direta sem fila.
  Não adiciona participantes a equipes nem cria vínculos ou permissões.
- A escolha explícita dispensa a configuração de destinatário/observador legado.
  Continua exigindo identidade autenticada, status inicial e prioridade normal.
  O fluxo sem escolha explícita conserva as validações dos padrões anteriores.
- O solicitante interno é exclusivamente o contato da própria conta com o e-mail
  da identidade autenticada, classificado como pessoa. Não depende de acesso ao
  cadastro comercial da empresa desse contato. O diretório e a abertura em nome
  de terceiros conservam as políticas existentes; a lista comercial não é ampliada.
- A leitura do contexto não autoriza a execução nem exige que o destinatário
  padrão esteja disponível. Criação/replay mantêm validação e fingerprint.
- O observador legado só é registrado se puder ver o chamado no destino final;
  a escolha de outro departamento não concede acesso a esse observador.
- Uma tela negada oferece navegação para Novo chamado. Essa navegação passa
  novamente pelo guard e recarrega o contexto; uma negação real permanece negada.
  Nenhuma regra de listagem, administração ou isolamento é removida.

## Validação e limites

Cobrir agente comum, destinatário em outro departamento, ausência de configuração
legada, padrão desabilitado, replay, destinatário revogado, outra unidade/conta
e recuperação de rota com nova checagem do servidor. Preservar as atualizações
da imagem f494fd38. CI, imagem publicada, implantação e aceite do Ronald são
etapas distintas. Sem alteração de dados produtivos ou implantação nesta etapa.
