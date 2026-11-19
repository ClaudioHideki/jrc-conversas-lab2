# ACW: autoridade atual e privacidade do estado observado

## Contexto e decisão

A precedência fila → equipe → geral e o bloqueio de conflitos já foram aprovados e validados em a16e8a49. Não são redefinidos neste incremento. A figura 9 também exige preservação do contexto autorizado ao alternar atendimento e perfil.

A revisão do hook nativo identificou que a identidade incluía conta e atendimento, mas não usuário/perfil. Uma consulta negada marcava erro sem apagar a projeção anterior. O novo incremento reutiliza o fingerprint nativo accountMembershipAccess e os endpoints existentes; não concede permissões no frontend nem modifica a autorização Rails.

- A identidade inclui usuário, tipo, vínculo da conta e capacidades atuais. Mudanças apenas de presença não reiniciam o formulário.
- Troca de conta, atendimento, autoridade, disponibilidade do módulo ou suporte de encerramento invalida leituras e escritas tardias e limpa projeção/rascunho anteriores.
- Falha de leitura oculta a projeção que não pôde ser revalidada. Negação 401/403/404 de leitura ou escrita também apaga o rascunho privado. Falhas transitórias de leitura e falhas ordinárias de gravação/validação preservam o conteúdo no mesmo contexto; a projeção só reaparece após nova leitura autorizada.
- Iniciar fica indisponível enquanto outra gravação está em curso ou o estado está sem validação. Perda da projeção não libera novas chamadas: o painel distingue situação não verificada de pós-atendimento comprovado, bloqueia nova discagem/atendimento e preserva rejeição e encerramento de chamada já existente. Os controles do servidor continuam obrigatórios.
- A consulta separada do estado do operador no workspace usa a mesma identidade de autoridade. Não há novo catálogo, banco, migration, comando de canal ou efeito PABX.

## Validação preparada

Dezesseis cenários novos do hook, três do workspace real e três do painel de voz, além dos existentes, foram preparados para ator/perfil na mesma conta, respostas tardias, negação de leitura e escrita, dupla submissão, preservação após 422, perda de suporte e presença. Os três arquivos de teste passam a integrar explicitamente o gate Vue existente, sem retirar qualquer caminho anterior.

ESLint estático: comparar os seis arquivos à base e preservar avisos preexistentes sem desativação. Testes Vue/Rails e a regressão Chrome do SHA próprio ainda são necessários. A fixture Chrome atual não monta o workspace completo de atendimento; seus cenários não provarão por si só a homologação visual deste trecho. Esse limite permanece explícito.

## Limites

Seleção intermediária persistida, relógio por motivo, formulários e automações de encerramento seguem pendentes. Os snapshots e as regras ACW anteriores não são alterados. Não é conclusão da figura 9, das etapas 0–2 nem das 23 referências. Nenhuma operação de produção, build de imagem, publicação, deploy ou PABX.
