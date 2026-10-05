# Roteiro de homologação — Backoffice integrado

## Pré-condições

1. Aplicar migrations em PostgreSQL de LAB.
2. Subir Rails/Sidekiq/Vite do LAB.
3. Usar uma account com CRM/Backoffice habilitados.
4. Ter ao menos um Pedido real do fluxo comercial.

## CT-BKO-01 — Elegibilidade Pedido → Backoffice

1. Criar/usar Pedido em `pending`.
2. Abrir Backoffice → Nova solicitação.
3. Confirmar que o Pedido aparece em **aguardando**, com motivo/status, e não entre elegíveis.
4. Alterar o Pedido para `approved` pelo fluxo normal.
5. Confirmar criação automática da Solicitação fulfillment.
6. Se a automação não tiver sido disparada para um Pedido legado aprovado, confirmar que o Pedido aparece como **elegível** para criação manual.
7. Confirmar que `canceled` não é elegível.
8. Confirmar que Pedido já vinculado aparece como **já vinculado** e não gera duplicidade.
9. Confirmar dados exibidos: pedido, cliente, produto/serviço, valor, MRR, status, Negócio, Proposta, Contrato e responsável quando existentes.

## CT-BKO-02 — Contrato único

1. Abrir uma Solicitação criada a partir de Pedido com Contrato CRM.
2. Confirmar que o ID/número do contrato é o mesmo de CRM → Contratos.
3. Confirmar ausência de segunda estrutura de contrato no Backoffice.

## CT-BKO-03 — Documentação

1. Selecionar uma Solicitação ainda sem documento.
2. Cadastrar/adotar requisito obrigatório e bloqueante.
3. Tentar aprovar sem anexo: deve bloquear e informar o motivo.
4. Anexar documento e aprovar.
5. Confirmar registro em `document_validations`/histórico.
6. Criar requisito condicional por produto/origem e validar que só aparece quando a condição é verdadeira.
7. Rejeitar requisito bloqueante: Solicitação deve ficar bloqueada.
8. Aprovar todos os bloqueantes: etapa documental deve tentar liberar automaticamente o próximo gate sem ignorar Contrato/Implantação/Provisionamento pendentes.

## CT-BKO-04 — Pendências

1. Criar pendência não bloqueante: fluxo não deve ser bloqueado.
2. Criar pendência bloqueante: Solicitação deve ficar `blocked`.
3. Informar área, responsável, prioridade e prazo.
4. Anexar evidência.
5. Devolver para outro responsável e confirmar histórico; quando houver Negócio, conferir atividade na Agenda/CRM.
6. Tentar resolver sem solução: deve falhar.
7. Resolver com solução: gravar usuário/data/hora e desbloquear apenas se não houver outro bloqueio.
8. Reabrir: manter histórico anterior.
9. Confirmar que não existe ação de exclusão silenciosa.

## CT-BKO-05 — Filas

1. Criar fila por empresa/unidade/tipo/produto/prioridade/equipe.
2. Testar Manual.
3. Testar Round Robin com pelo menos dois usuários.
4. Testar Menor Carga.
5. Testar Especialidade/Regra.
6. Confirmar fila e responsável gravados na Solicitação e no histórico de alterações.

## CT-BKO-06 — SLA

1. Criar política com primeira ação, etapa e SLA total curtos no LAB.
2. Definir calendário e feriado de teste.
3. Confirmar cálculo de vencimentos.
4. Colocar Solicitação em status configurado como pausa; confirmar `sla_paused_at` e auditoria.
5. Retomar; confirmar deslocamento de deadlines e evento de retomada.
6. Validar estados 50%, 75%, 90%, 100% com job do monitor.
7. Confirmar escalonamento após 100% quando configurado.
8. Confirmar cards de dentro do prazo/atenção/crítico/vencido, primeira ação vencida, cumprimento e tempo médio.
9. Confirmar volume por fila.

## CT-BKO-07 — Regressão

Validar que continuam operacionais:
- aceite digital da Proposta;
- Proposta aceita → Pedido;
- integridade Cliente/Negócio/Proposta no Pedido;
- Pedido → Contrato;
- CRM-ORD-CONTRACT-01;
- Metas/ações inteligentes;
- Projetos, Service Desk, Minha Agenda e Cadastro Mestre.

## Gate de saída

Não promover a produção até concluir:
- migrations PostgreSQL;
- RSpec relevante;
- Vitest/build Vue;
- browser;
- build Docker/GHCR.
