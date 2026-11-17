# ADR 0005: Encerramento manual sem bloqueio por configuração de SLA

- Status: Aceita para implementação a pedido do usuário
- Data: 2026-11-17

## Contexto e decisão

O usuário apresentou o bloqueio de encerramento de um chamado antigo por ausência
de meta e calendário de SLA e autorizou retirar os requisitos de encerramento
para os usuários. A base é a imagem atual a5d5e1a, preservando as correções de
destinatários, Projetos, indicadores, popup e mensagens.

O fluxo manual de Encerrar chamado passa a enviar uma intenção explícita de
encerramento operacional. Funcionários com acesso ao chamado em sua unidade,
incluindo administradores, podem confirmar sem depender de uma permissão extra
de fechamento, leitura de notas/SLA/histórico, papel administrativo na política,
aprovação, evidência, classificação, solução ou motivo obrigatório. A regra
prospectiva substitui as restrições anteriores somente nesse fluxo manual.

Mantêm-se conta/unidade e visibilidade, autoria real, etapas válidas do ciclo,
versão esperada, lock do comando, chave de idempotência, readback e auditoria.
Conteúdo protegido não é liberado por permitir encerrar: quem não pode ler notas
ou histórico não recebe esses campos. O próprio recibo de um encerramento manual
pode ser confirmado pelo autor sem conceder leitura do histórico de terceiros.
Executores automáticos não podem usar a intenção manual para obter permissões.

## Tempo e SLA

Com meta e calendário válidos, o comando conclui os relógios de atendimento e
resolução no instante real e preserva metas, prazos, pausas e resultados já
medidos, inclusive violações. Encerrar não equivale a ter dado primeira resposta:
um relógio ainda sem essa evidência é parado, sem fabricar um cumprimento.

Sem configuração válida, o encerramento prossegue, fecha a pausa corrente e
registra cálculo pendente. Autoria, resolução, encerramento e tempo de parede
continuam disponíveis nos fatos nativos e nos indicadores de conclusão. Não se
cria uma meta ou um calendário fictício e não se marca SLA sem medição como
cumprido. Políticas e snapshots históricos permanecem imutáveis.

## Verificação e limites

Regressões cobrem perfil com somente leitura do chamado, política antiga
restritiva, ausência de metas, aprovação pendente, conclusão com SLA real,
replay sem duplicidade e rejeição de outra unidade/executor automático.
29 testes locais de interface aprovados. Integração nativa e imagem pendentes
na abertura deste registro. Sem migration nova ou implantação em produção.

### Fechamento da publicação

Em 17/11/2026, integração 44139348538 e build 44142694078 aprovaram o produto
`688626104ca89001a74da142d121610509254025`. Imagem publicada e conferida diretamente
no GHCR pelo digest `sha256:53b9ebc6f5938e40c3294d4487b894474b9ced88464cd707a60a1794957ee57a`,
com linux/amd64 e label da revisão exata. Suíte principal Rails1303, frontend1617
na integração/2757 no build e24 cenários de navegador aprovados; smokes de aplicação
e worker antes/depois da publicação aprovados. [Registro da release](../jrc_consolidation/encerramento-livre-sla-release-20261117.md).
Não houve implantação em produção nem merge em main neste incremento.

### Correção posterior do transporte da interface

O usuário apresentou uma falha de confirmação após implantar a imagem 68862610.
A revisão pública do servidor confirmou esse SHA. A interface gerava corretamente
`operational_closure`, mas a lista de campos do cliente HTTP não o admitia. A
exceção local interrompia o comando antes do POST; retirar requisitos somente no
servidor não resolvia esse ponto.

Dois cenários do formulário com o cliente HTTP real e transporte sintético
reproduziram zero envios, com motivo vazio e com motivo preenchido. A correção
admite o campo oficial no cliente, mantendo os demais campos e verificações de
conta, autoria e confirmação. Não altera políticas, medições nem o servidor de
produção. Novos testes, integração e imagem devem ser concluídos nesta revisão.

Após admitir o campo, os dois cenários enviaram resolução e encerramento pelo
cliente real, com chaves de idempotência e releituras independentes de transição,
chamado e ciclo. A suíte local de formulário, contratos e ligação Vue passou
72 testes; ESLint dos dois arquivos alterados ficou sem erros, com três avisos
preexistentes de texto sintético no spec. Integração e imagem ainda pendentes.
