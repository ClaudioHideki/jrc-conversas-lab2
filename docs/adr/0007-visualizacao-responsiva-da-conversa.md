# ADR 0007: Priorizar as mensagens quando a área de atendimento é pequena

- Status: Aceita para implementação
- Data: 2026-11-18

## Contexto e decisão

O usuário apresentou uma conversa em que cabeçalhos, três colunas e o editor
deixavam pouca altura para ler mensagens em alguns monitores. A revisão pública
era d3d66232. A base e6bd4cc9 preserva esse produto e acrescenta somente os gates
de CI já integrados na main.

O layout passa a considerar o espaço efetivo do atendimento, além da largura da
janela. Com menos de 1120 pixels de largura útil, o contexto do cliente continua
acessível pelo popup existente. Com menos de 620 pixels de altura útil, margens,
cabeçalhos e faixas de origem ficam compactos. As letras e as mensagens não são
reduzidas. A cadeia flex da conversa passa a permitir encolhimento e rolagem.

O editor usa uma altura inicial menor quando sua área tem menos de 520 pixels.
Os limites consideram a altura real dos controles ao redor e são recalculados
quando a área muda. A altura manual continua limitada pelo espaço disponível.
Expandir, arrastar e restaurar o editor permanecem disponíveis.

O botão Ampliar conversa recolhe lista, contexto lateral e abas auxiliares. A
identificação da conversa e as origens de recebimento e resposta permanecem
visíveis. Lista e cliente podem abrir temporariamente; Restaurar painel devolve
as colunas e abas. A conversa e o editor permanecem montados, preservando o
rascunho. Trocar de conta encerra o modo ampliado. A jornada de voz é preservada.

## Evidência e limites

200 testes existentes de caixa de entrada e componentes de conversa passaram
em 20 arquivos. ESLint dos componentes alterados sem erros; quatro avisos
preexistentes. Não foram criados estilos de produto fora de Tailwind.

O laboratório Chrome compilou os componentes nativos de layout com mensagens e
controles de envio sintéticos. Foram comparados 1280x625, 1366x768, 1920x1080 e
1024x600. Sem erro de navegador ou rolagem horizontal; o editor ficou no viewport
após redução de altura, e o rascunho foi preservado ao ampliar/restaurar. Popup
do cliente, Escape, lista recolhida e expansão do editor foram verificados.

Em 1366x768, a altura da lista de mensagens passou de 169 para 285 pixels,
ou 334 no modo ampliado. Em 1920x1080, a área normal manteve 1025x481 pixels e
as três colunas. São medidas do laboratório, sem dados reais de clientes;
não representam aceite operacional em todos os monitores.

Imagem e verificações da publicação pendentes na abertura deste registro.
Sem migration nova, mudança de permissões, envio real, backup, dump, restore
ou implantação em produção neste incremento.

## Ajuste necessário no runner de publicação

A execução 44361164573 aprovou as duas regressões iniciais, mas a preparação
do build atingiu oito minutos baixando pacotes de us-east-2.ec2.archive.ubuntu.com.
A seleção de espelho saudável não era aplicada a esse hostname do runner.
O redirecionamento de fontes apt passa a reconhecer os subdomínios oficiais de
archive/security.ubuntu.com, incluindo EC2. Pacotes, assinaturas, verificações,
retries e limite de tempo permanecem iguais. O produto visual não mudou.
Uma nova revisão deve concluir a construção e a publicação.

## Fechamento da publicação

Em 18/11/2026, o build 44363528959 aprovou a revisão
`f494fd38dd62929303279d39b4591372ac72e607`, com 296 arquivos/2759 testes
frontend, 168 exemplos Rails e smokes de aplicação/worker antes e depois
da publicação. Digest `sha256:e1502e545cb9b4dc6c96eab2fd9068c5052ccc8fe0c02960b50ae7d3d3fb61dc`,
linux/amd64 e revisão exata conferidos diretamente no GHCR.
[Registro e referência da imagem](../jrc_consolidation/inbox-responsive-release-20261118.md).
Sem implantação em produção ou merge em main neste incremento.
