# Conexões WhatsApp — candidata baseada no Word

## Alterações implementadas

- Lista horizontal responsiva, identificação da caixa, estado e horários informados pela origem; tabela de distribuição, filas, modo e estado da política.
- Navegação por conexão, menu de ações, ajuda contextual e edição em cinco abas: visão geral, distribuição, regras/horários, histórico e configurações.
- Mesma máquina de pareamento, autorizações e inbox preservadas. Abrir a página/modal não solicita QR. Contador usa `expiresAt` real e descarta o código ao expirar/fechar.
- Administrador pode configurar a distribuição local mesmo quando a consulta de estado do Broker falha. Pareamento continua autorizado e validado no backend.
- Política grava em uma operação auditada; nome usa configuração separada. Nenhum save redistribui conversas já atribuídas.
- GET `.../jrc_broker/inboxes/:inbox_id/summary`: métricas persistidas de 30 dias, amostras e janela UTC. Relatórios exigem permissão; configuração de filas exige gestão. Não consulta o provedor.
- Histórico rejeita observações mais antigas e associa resultados à chave/operação correta, preservando o ator de tentativas concorrentes.

## Verificações locais

A regressão da página/lista/cinco abas falhou antes da alteração. O novo teste de edição offline também falhou antes da correção e passou depois.

- Suíte de componentes Broker: 96 testes, zero falhas e pendências.
- Página após revisão e novo teste offline: 27 testes, zero falhas e pendências. Os demais componentes não foram alterados pela correção offline.
- ESLint dos componentes/cliente API: zero erros; avisos de chaves de tradução dinâmicas devem ser distinguidos de erro de lint.
- Build local completo foi interrompido para reduzir concorrência de recursos. Não representa build aprovado; a CI desta candidata executa o build completo.
- Testes Rails completos ainda precisam da CI com PostgreSQL/Redis e schema/migrations atualizados. O runner local existente parou com 25 migrations pendentes antes de executar exemplos, após carregamento de gems anormalmente lento.
- A suíte isolada do histórico executa a classe real com binding em memória; não substitui os testes Rails/PostgreSQL.
- A conferência visual pelo controle do navegador foi interrompida por impossibilidade de confirmar a URL. O laboratório e E2E em CI usam componentes reais, respostas sintéticas e nenhum telefone/credencial real.

## Limites e pendências explícitas

`connectedAt` permanece ausente quando o Broker não tem evidência confiável do início da sessão. `lastSyncAt` é a última entrega de entrada confirmada, não o horário da consulta.

Agentes elegíveis agora permanece `null`: contar usuários ou aplicar outro filtro daria um resultado diferente do dispatch, especialmente no overlay Enterprise. Não apresentar como métrica homologada.

A engine não fornece atualmente um motivo de expiração de sessão normalizado no contrato de saúde. Expiração de QR é tratada, mas não equivale a logout da sessão. Falta a política de propriedade organizacional do mesmo número QR entre instâncias distintas. Não alterar silenciosamente fingerprints de identidades já aprovadas.

A correção correspondente no Broker está em branch separada: QR/código emitido não produz `INSTANCE_CONNECTED`, e resultado tardio de pareamento não sobrescreve callback autenticado mais novo. Não é uma nova homologação de número real.

Nenhuma sessão, credencial, campanha ou configuração produtiva foi alterada neste incremento. Sem backup/dump/restore. Nenhuma migration nova é necessária para estas alterações.
