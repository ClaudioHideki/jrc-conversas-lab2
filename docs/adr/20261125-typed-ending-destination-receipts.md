# Recibos independentes dos destinos de encerramento

Estado: preparação privada, sem aceite nativo ou habilitação operacional.

## Problema

A execução original de Projetos já possui origem, autorização, auditoria e
recibos imutáveis. Seu histórico identifica tarefas de Projetos. Utilizar o
mesmo identificador para representar Lead, atividade ou chamado reinterpretaria
evidências existentes e permitiria confundir recursos de módulos diferentes.

## Decisão

Preservar os modelos e SQLs publicados do fluxo original. Reutilizar catálogo,
versões, origem, habilitação prospectiva, confirmação de encerramento e o
contexto do agente original. Acrescentar somente o histórico técnico necessário
para distinguir consentimento de ação, tentativa, sucesso nativo e resultado
independente de cada destino. Os cadastros e serviços dos módulos permanecem
as fontes dos recursos de negócio.

O seletor interno admite somente operações conhecidas e seus serviços nativos:
tarefa de Projetos, Lead e atividade CRM, criação e edição de chamado do
Service Desk. Não aceitar nomes de classes, usuário executor, permissões ou
identidades corporativas como concessões fornecidas pelo cliente.

Cada tentativa pendente reautoriza o agente que realmente participou do
atendimento. Um resultado terminal apenas reconhece uma entrega interna
repetida; não autoriza consultar seu destino. O efeito nativo, sua auditoria e
o recibo de sucesso pertencem à mesma transação. Uma falha precisa desfazer
essa transação antes de registrar um código limitado de resultado, sem texto
privado de exceção. Os demais destinos conservam seus próprios resultados.

Uma nova tentativa exige revisão explícita do agente original e referência
exata ao último predecessor malsucedido. A chave do efeito permanece a mesma.
Uma tentativa bem-sucedida não pode ser repetida nem adquirir outro efeito.
Desativar uma regra bloqueia suas pendências anteriores permanentemente;
reativação não remove essa barreira.

Confirmar a classificação não equivale a consentir uma ação manual nem concluir
o ACW. O modo de execução deve permanecer explícito e os três fatos separados.
Os eventos NICO eventualmente produzidos pelo serviço nativo somente podem ser
entregues depois do commit efetivo, utilizando a proteção de transporte já
existente. Não há comandos ou publicação de configurações no PABX.

## Limites deste incremento

A preparação não cria rota, grant, ativação ou entrega automática nova. Não é
uma plataforma paralela de automação. A atualização de oportunidades, escolha
operacional de chamado/revisão transitória, criação CRM com escopo inequívoco,
configuração pública, confirmação manual na interface, recuperação operacional,
notificações e orquestração NICO continuam exigindo implementação e validação
próprias antes da habilitação correspondente.

Os testes preparados incluem instalação, atualização populada, reexecução,
recarga, imutabilidade, ciclo da conta, transações e contenção PostgreSQL real.
Os cenários mistos devem provar CRM preservado após falha real do recibo do
Service Desk e nova tentativa somente desse destino. Provas por configuração
direta sintética não substituem APIs ou Chrome. Até a execução e a verificação
dos relatórios, esses casos são preparação, sem aceite da figura 10 ou da
Parte 1.
