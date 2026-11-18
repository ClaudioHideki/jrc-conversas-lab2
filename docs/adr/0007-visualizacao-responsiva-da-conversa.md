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
