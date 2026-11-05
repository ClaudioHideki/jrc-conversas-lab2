# Validação do fluxo do Thiago — pausas, escalas e distribuição

## Resultado

O fluxo recebido é compatível com a distribuição central implementada no incremento 4724688e. A diferença principal confirmada pelo usuário foi a necessidade de **escala própria para cada agente**. A candidata anterior tinha expediente da caixa e pausas manuais, mas não uma escala semanal individual.

Este incremento adiciona a escala individual e corrige lacunas de horário e manutenção. As alterações estão somente no JRC Conversas LAB2, na branch local codex/shared-inbox-history-20261104. O Broker continua responsável pelo transporte e identidade da caixa; as decisões humanas de horário, fila e responsável são do JRC. Não houve alteração produtiva, push, merge, imagem, deploy, credenciais, engine, conexão ou mensagem real.

Fonte: anexo a0138809-2f81-46f5-9188-9f38eec62c67/Texto colado.txt, SHA-256 6ab6ccd346b510826e846d37ace1ae73804029d08d39810086771b653d71cd4c. Complemento confirmado pelo usuário: “Cada agente terá sua própria escala”.

## Confronto com o que existia

| Regra do fluxo | Situação e evidência |
| --- | --- |
| Pertencer à caixa e ao time | Já implementado; revalidado no servidor e sob locks de distribuição. |
| Distribuição automática habilitada | Já filtrava agentes; acrescentado despertar imediato da fila ao reabilitar a opção para agente disponível. |
| Disponível e com sessão presente | Já implementado, com presença Redis e status no banco; não basta ter o navegador aberto. |
| Pausa, almoço, reunião, fim de expediente e demais indisponibilidades | Já bloqueavam novas atribuições. Todos os nove estados diferentes de online foram exercitados mantendo o atendimento existente. |
| Preservar o responsável ao pausar | Já implementado; não foi adicionada redistribuição automática dos atendimentos atuais. |
| Expediente da caixa | Já configurável. Corrigido o caso em que desabilitar o calendário depois de salvar a política liberava atribuições como se fosse 24 horas. |
| Escala de cada agente | Adicionada: semana por agente/caixa, intervalos de trabalho e almoço, dias de folga e turnos noturnos. |
| Conferir horário antes de gravar atribuição | Acrescentada revalidação de calendário e escala dentro da decisão final, cobrindo fechamento enquanto a atribuição estava em andamento. |
| Menor percentual de ocupação e empate por round robin | Já implementado e preservado. |
| FIFO por solicitação original | Já implementado e preservado; uma mensagem nova não reinicia a posição. |
| Retorno do agente e liberação de capacidade | Já havia recuperação ao voltar, resolver/suspender ou alterar atribuição; testes cobrem atribuição sem intervenção do supervisor. |
| Início de expediente/escala | O RecoveryJob existente, configurado a cada minuto, reconsidera as solicitações persistidas com os horários atuais. Não há novo scheduler nem necessidade de liberação manual no servidor. |
| Mensagem automática, Flow de fora do horário, bot ou plantão | O texto apresenta essas ações como futuras e dependentes de configuração. Este incremento mantém a fila; não cria respostas ou automações incondicionais. |

## Escala individual implementada

- Configuração por agente **na distribuição de cada caixa**, no fuso horário da caixa. Um agente em caixas diferentes pode ter configurações diferentes.
- Sete dias da semana e até quatro períodos por dia. Exemplo: 09:00–12:00 e 13:00–18:00.
- Dia sem períodos é folga, exceto a continuação de um período noturno iniciado no dia anterior. Turnos que atravessam meia-noite e sábado/domingo são avaliados corretamente.
- O fim do período individual é exclusivo: 12:00 já está fora do período 09:00–12:00. O contrato aceita 24:00 somente como encerramento de dia inteiro; a interface normaliza o preenchimento de meia-noite independentemente da ordem de edição.
- Períodos sobrepostos, horários malformados, semanas incompletas e IDs de agentes fora da caixa/tenant são rejeitados antes da gravação.
- A escala individual não muda automaticamente o status do agente. Uma pausa/almoço manual continua bloqueando novas atribuições até ele voltar a disponível, mesmo se estiver dentro da escala.
- O expediente da caixa e a escala individual se acumulam. Um agente com turno noturno só recebe à noite se a regra da caixa também permitir aquele horário.
- Ausência de escala individual mantém a herança da regra anterior da caixa para compatibilidade. Não foram inventadas escalas reais para os funcionários nem ativadas regras de produção.
- Escalas são armazenadas no JSON da política existente e no histórico PostgreSQL de mudanças; não foi criada migration.

## Configuração na interface após publicação

1. Em Configurações → Caixas de Entrada, conferir agentes, times e fuso/horário de funcionamento.
2. Em Conectar seu WhatsApp → Gerenciar conexão → Distribuição, escolher a política exclusiva, supervisores, times e capacidades.
3. Em **Regras e horários → Escalas individuais**, selecionar o agente e ativar sua escala individual.
4. Cadastrar os períodos de cada dia, deixando os intervalos de almoço e folgas sem período. Salvar a distribuição.
5. Repetir para os demais agentes. Manter disponibilidade, capacidade e fila de espera habilitadas na caixa central.
6. O agente deve usar Disponível para receber e Pausa/Almoço/Fim de expediente quando não puder assumir novos atendimentos.

Se um agente com escala salva sair da caixa, o editor mostra a entrada antiga e permite remover explicitamente a escala e as referências antigas de capacidade/supervisão daquele ex-membro antes de salvar. A política não é apagada silenciosamente e o histórico anterior é preservado.

## API e compatibilidade

A rota existente GET/PUT `/api/v1/accounts/:account_id/jrc_broker/inboxes/:inbox_id/distribution` recebeu o campo aditivo `agent_schedules`. Não há novo endpoint nem mudança na API de transporte do Broker.

```json
{
  "agent_schedules": {
    "123": {
      "0": [],
      "1": [{"start":"09:00","end":"12:00"},{"start":"13:00","end":"18:00"}],
      "2": [], "3": [], "4": [], "5": [], "6": []
    }
  }
}
```

0 representa domingo e 6 sábado. O exemplo permite atendimento apenas na segunda-feira. Um cliente antigo que omita o campo preserva as escalas já salvas. Enviar objeto vazio remove as escalas individuais e restaura a herança; essa alteração é auditada. GET e PUT continuam administrativos, com isolamento de Account/inbox e sem chamadas pagas ou acesso à Evolution.

O binário antigo não conhece escalas individuais. Não ativar essas regras com web/Sidekiq de versões diferentes, nem voltar ao binário antigo mantendo a expectativa de aplicação das escalas. A proteção da exclusividade do incremento anterior continua exigindo versão consistente em todos os processos.

## Reprodução e correções

O primeiro conjunto novo de integração teve 17 exemplos, 7 falhas: campo ainda não aceito, calendário desabilitado, passagem do horário antes da gravação e reabilitação da distribuição sem despertar imediato. As falhas foram corrigidas; os estados de pausa já passavam.

Os dois primeiros testes da interface falharam pela ausência do editor. Depois foram adicionados testes de revisão: remoção de escala de ex-membro e preenchimento de dia inteiro, que falharam antes da correção.

Uma execução ampliada encontrou um problema de isolamento do próprio teste: o RecoveryJob processa várias Accounts de teste, enquanto o stub de presença aceitava apenas a Account do exemplo. O stub recebeu fallback para o serviço real nas outras Accounts, sem alterar o comportamento produtivo. A regressão ampliada seguinte passou.

## Revisão independente

- Importante: escala de agente removido tornava a política impossível de salvar. Corrigido com remoção explícita da entrada antiga no editor; validação de membros continua obrigatória.
- Menor: preenchimento de dia inteiro dependia de editar início antes do fim. Corrigido e testado nas duas ordens.
- Menor: novos rótulos ainda usam fallback inglês em pt_BR. A regra do AGENTS.md exige alterar somente os catálogos en e encaminhar traduções pelo Crowdin; não foi alterado o catálogo português neste incremento.
- Fora deste incremento: calendário corporativo único, feriados/exceções de datas e planejamento de força de trabalho. A escala entregue é semanal e por caixa. Horário de verão segue os períodos locais do fuso configurado, inclusive a repetição de horas; não foi inventada uma política trabalhista diferente.

## Resultados dos gates

- RSpec ampliado: **308 exemplos, 0 falhas**, com PostgreSQL e Redis locais descartáveis e gate de concorrência habilitado.
- Após a revisão e a refatoração do validador: **107 exemplos de serviços/concorrência/jobs/API, 0 falhas**. São conjuntos sobrepostos, não 415 testes independentes.
- Vitest final após a revisão: **24 arquivos, 227 testes, 0 falhas**. Depois dos últimos ajustes de marcação e remoção de configurações do ex-membro, o conjunto focado de interface foi executado novamente (44 testes); não somar as execuções repetidas.
- Prettier: arquivos JS/Vue/JSON alterados formatados. ESLint final: **0 erros, 22 avisos**, todos remanescentes do componente de distribuição anterior.
- RuboCop Lint: **9 arquivos, 0 ofensas**. Ruby sintaxe: 9 arquivos válidos. RuboCop completo: baseline 25 ofensas em 6 arquivos, candidata 21 em 9; permanece débito de métricas/estilo, incluindo complexidade da seleção e teardown explícito no novo teste. Não declarar lint integral limpo.
- Build completo e CI no SHA novo: **não executados neste incremento**. O build completo permanece um gate pendente após o OOM local do incremento anterior. E2E de navegador, scheduler/Sidekiq produtivos e WhatsApp real não homologados nesta tarefa.

## Limites para publicação

O scheduler e os workers default/scheduled_jobs precisam estar ativos para executar a recuperação periódica. Foi validado o código do agendamento e executado o job e suas chamadas de distribuição pelo adaptador de testes ActiveJob, com PostgreSQL/Redis reais no laboratório; não foi comprovado nesta tarefa que o scheduler produtivo está rodando. A recuperação depende do próximo ciclo e da capacidade dos workers, não de uma garantia de atribuição no segundo exato de abertura.

Ainda são necessários build completo/CI no SHA exato e E2E em navegador antes da promoção. Não foi repetida a tentativa de build completo já bloqueada por OOM no incremento anterior. Não houve nova imagem, deploy ou homologação de WhatsApp real. A integração remota da URA Broker e a sincronização integral do histórico mantêm seus gates próprios.

Não foram executados backup, dump, restore, limpeza de clientes ou alteração de sessões reais.