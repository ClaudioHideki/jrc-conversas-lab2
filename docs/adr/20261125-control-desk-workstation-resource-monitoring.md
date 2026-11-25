# Monitoramento de recursos da estação durante o desenvolvimento do Control Desk

Status: aceito por autorização expressa do usuário.

A disponibilidade de RAM do Windows é um indicador de monitoramento. O antigo
bloqueio obrigatório de 1,5 GiB foi revogado pelo usuário. Uma leitura abaixo
desse valor, isoladamente, não suspende o desenvolvimento.

As operações locais permanecem leves: leitura, alterações incrementais,
checkpoints e conferência limitada de evidências. Builds e testes pesados
permanecem nos runners isolados do GitHub. Esta decisão não reduz as reservas
nem os requisitos próprios dos runners e dos builds autorizados.

Falha efetiva do ambiente, impossibilidade técnica de continuar ou risco
concreto de perda de dados continuam exigindo interrupção segura da operação
afetada. As reservas de disco e os limites de leitura dos artefatos permanecem
ativos. Nenhuma limpeza, encerramento de processo ou alteração de infraestrutura
é autorizada por esta decisão.

Continuam preservados a main, o checkout original, seus arquivos pendentes,
Docker, WSL, o servidor 5379 e os demais ambientes. Os gates de identidade,
migrations, permissões, testes e integridade das evidências mantêm seus critérios.

Esta decisão não autoriza merge, publicação de imagem, deploy nem alterações em
produção. Os checkpoints intermediários não representam conclusão da Parte 1.
