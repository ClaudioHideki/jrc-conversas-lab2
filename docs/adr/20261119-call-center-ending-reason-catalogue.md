# Catálogo administrativo de motivos de encerramento

Data: 19/11/2026. Estado: incremento preparado; aprovação nativa ainda pendente.

Os dois Word pedem nome, categoria, descrição, ordem, status, uso em regras de ACW,
obrigatoriedade por fila e automações. Este incremento entrega o catálogo administrativo
na configuração nativa de ACW. A obrigatoriedade operacional por fila, labels congelados
por atendimento e as automações por destino continuam pendentes; não são inferidas deste catálogo.

## Decisão

- Usar `Account.settings[jrc_contact_center_acw][voice_reason_catalog]` e a API de política já existente.
  Não criar endpoint, tabela de usuários, cadastro de clientes, permissão ou serviço externo paralelo.
- Catálogo versionado com até 100 motivos e 128 KiB. Código de até 100 caracteres;
  nome/categoria até 120; descrição até 2000; ordem inteira 0–1000; status booleano literal.
- Código persistido não é removido/renomeado; a retirada é por desativação. Nome, descrição,
  categoria, ordem e status são editáveis. A auditoria nativa de ACW guarda antes/depois,
  versão, ator e request_id na mesma transação. Ausência do catálogo conserva o hash legado.
- As mesmas permissões `configure?` e cobertura corporativa global protegem a leitura e escrita.
  Operadores e gestores restritos não recebem o catálogo completo. IDs e revisão não concedem acesso.
- Cada gravação requer revisão atual. Após conflito a interface conserva o rascunho e exige revisão
  explícita; ao reconciliar usa os limites de canal mais recentes para preservar campos não editados.
  Falha incerta não provoca repetição automática. Dados são apagados da interface após acesso negado.
- Reutilizar Dialog, API, cores/temas e controle de conflito nativos. Filtros locais e paginação de 10
  trabalham sobre a coleção limitada a 100. Motivos ativos passam a ser opções nomeadas no editor
  de regras; códigos antigos/inativos já usados continuam visíveis sem reativação automática.
- Nenhuma regra v1, formulário, resposta, qualificação ou snapshot histórico é reescrito.
  Nenhuma automação, PABX, alçada, catálogo de produção ou operação externa é ativada.

## Verificação exigida

RSpec com PostgreSQL descartável: persistência, auditoria, versões, idempotência, CAS,
rollback de auditoria, isolamento, perda de permissão/cobertura, entradas malformadas e
preservação de atendimento já capturado. Vue: conflitos, resposta incerta/tardia, conta,
duplicidade, edição, paginação e descarte explícito. Chrome real nos quatro projetos,
com CSS compilado neste próprio SHA, cria/edita/recarrega/desativa e seleciona o motivo
na regra nativa sem ativá-la. Contagens positivas e zero falhas/pendências são obrigatórias.

O aceite desse incremento não conclui as figuras 9/10 nem a integração com automações.


## Validação nativa e complemento aprovado

A primeira rodada f89707d5 confirmou 1566 exemplos Rails core, com quatro falhas,
e 66/66 na recarga de schema. Oito infrações novas de layout Ruby. Vue/Chrome não
foram executados. O verificador estrito também recusou duas identidades lógicas
iguais em casos de nome mínimo/máximo; os nomes devem ser distintos, sem deduplicar.

A entrada `[null]` era normalizada para `[]` pelo deep-munge antes do domínio.
O novo campo é recuperado exclusivamente de JSON tipado, com o decodificador nativo
ActiveSupport e corpo limitado a 1 MiB. Apenas esse campo segue para o validador
existente. A autenticação e o escopo continuam nativos; nenhuma configuração global
de parsing muda. Null/false e campos desconhecidos não são filtrados para produzir
uma configuração válida. Os testes de revisão usam o token HTTP atual; o teste do
hash preserva exatamente o vetor de seis campos v1, sem depender da ordem JSONB.

O usuário aprovou exigir motivo cadastrado em toda chamada das filas selecionadas,
preservando os atendimentos já iniciados. A implementação operacional dessa regra
continua pendente. A versão deve ser vinculada ao início da chamada, com origem
nativa e proveniência verificável, sem impor a configuração nova retroativamente.
