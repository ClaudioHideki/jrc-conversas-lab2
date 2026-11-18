# Catálogo local de motivos de pausa

Status: implementação candidata; depende de execução nativa e homologação Chrome próprias.

## Decisões aprovadas

O usuário aprovou preservar motivos livres e eventos legados. Exigir catálogo somente após ativação explícita por conta. Não ativar contas reais. A retirada do último agente elegível de fila ativa requer confirmação do gestor, revisão e auditoria; sua implementação é um incremento independente, sem obrigação de aprovação formal e sem publicação no PABX.

## Implementação

Reutilizar Account.settings, AgentStateManager/Event, disponibilidade nativa, Account mutex, ModulePolicy, OrganizationalScope, QueueMembership e a auditoria administrativa. Não criar cadastro paralelo de usuários, disponibilidade ou distribuição. Configurar somente com permissão nativa e cobertura global. Unidades e perfis do motivo restringem o público já autorizado, nunca concedem acesso.

Configuração global limitada a 100 motivos, com código estável, categoria, descrição, status e tempos HH:MM convertidos em minutos inteiros. Revisão obrigatória vinculada à conta; conflito exige carregar, comparar e confirmar novamente. Ativação exige confirmação literal, separada de salvar um motivo. Alterações e auditoria são atômicas. Formatos malformados não são filtrados para escopo global.

Novas pausas verificam o catálogo atual depois de obter os locks nativos. Recibos antigos continuam sujeitos à autorização atual, mas seu replay exato não é reinterpretado como uma nova pausa. Eventos preservam o retrato do motivo no momento da criação. Projeção pública reautoriza proprietário, conta, perfil e unidades e omite IDs de escopo. Eventos do fornecedor não conferem autoridade ao catálogo.

## Limites observáveis

Catálogo é local. Tempos são informativos e geram aviso ao exceder o máximo; não alteram distribuição automaticamente. A proteção nativa contra pausa durante chamada continua aplicada. Regras avançadas de justificativa, aprovação, variabilidade e comportamento por fila ainda precisam do respectivo incremento interno. Comandos, publicação, ACK e versão aplicada continuam dependentes de contrato/homologação PABX indisponíveis. As figuras 7/8 e o conjunto das 23 imagens não são declarados concluídos.

## Validação preparada

Testes Rails de autenticação, escopo, configuração malformada, legado, replay, imutabilidade do retrato, revisão e auditoria; corridas HTTP com banco descartável e sem transação externa de fixture; Vue de formulário, HH:MM, paginação, conflito, revisão invalidada, escopo e troca de conta; Chrome real em quatro projetos para CRUD, paginação, ativação explícita, revisão concorrente e operação com exclusão da unidade não autorizada. O novo gate mantém 124 casos anteriores e exige 132 casos totais. Fixtures usam contas exclusivas sem canais/PABX, tokens privados temporários excluídos dos artefatos.

Resultados ainda não executados não são aprovação. Registrar SHA, relatórios, hashes e capturas após o checkpoint e a CI exclusivos deste incremento.
