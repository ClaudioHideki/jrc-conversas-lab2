# Calendário nativo em versões internas de URA

Status: implementação candidata, aguardando validação nativa e visual.

## Problema e decisão

Os dois Word exigem calendários reutilizáveis em filas e URAs. A biblioteca de horários já usa as regras e a matemática nativas do calendário do Service Desk, com isolamento próprio do Call Center. O vínculo de filas está separado da configuração efetivamente aplicada no PABX.

Acrescentar um nó interno de calendário ao grafo de URA existente, na versão3 do contrato local. Preservar a leitura, edição e simulação dos contratos1/2. Esta alteração não modifica o contrato do fornecedor, comandos, publicação de configuração ou migrations históricas.

## Autorização e histórico

O seletor lê o catálogo nativo da unidade autorizada e exige revisão explícita. O servidor revalida identidade, elegibilidade, permissão configure, conta, cobertura e unidade em cada operação. IDs, hashes e snapshots do corpo são seletores ou dados; não concedem acesso.

Um vínculo novo precisa corresponder exatamente ao catálogo e à revisão nativa atuais. A gravação usa a transação e os locks existentes. A referência histórica só pode ser reutilizada na mesma URA autorizada, com escopo imutável e versão nativa acompanhada da auditoria de criação que atesta a origem. A versão do contrato é imutável; não se presume que a tabela de auditoria seja selada. Ausência ou ambiguidade de atestação bloqueia a confiança histórica.

Alterar o catálogo não altera versões já salvas. Importar um JSON ou conhecer um hash não reproduz a autoridade da origem. Não há atualização automática de vínculos antigos ou permissões novas por cargo.

## Simulação observável

Exigir data/hora e fuso explícitos no editor; aceitar também instante ISO8601 com offset na API. Reutilizar SnapshotCalendar e a precedência aprovada: exceção explícita da data, feriado, expediente semanal. Recusar horários locais inexistentes ou ambíguos por DST, entradas malformadas, destinos ausentes e ciclos sem saída. Invalidar a prévia após qualquer alteração de grafo, unidade, instante ou origem.

A tela e o resultado identificam a operação como local, sem aplicação no PABX. A presença de um calendário ativo no catálogo não prova roteamento operacional.

## Critérios e limites

Os91 testes Vue direcionados usam HTTP simulado e não provam autorização Rails. Preparar testes nativos de conta/unidade/origem, fonte alterada, histórico, replay, trigger imutável e espera real por lock. Acrescentar um cenário Chrome em cada um dos quatro projetos existentes: todos os244 anteriores permanecem e o gate passa a exigir248, com zero falhas, pendências, erros e resultados instáveis.

O inventário de referências correntes de URA na biblioteca de calendários continua separado e pendente. Números e publicação operacional dependem de contrato nativo/fornecedor comprovado. Esta decisão não conclui os23 referenciais visuais ou a homologação externa.
