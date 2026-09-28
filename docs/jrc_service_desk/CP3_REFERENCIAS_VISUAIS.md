# CP3 - Referências originais e adaptação nativa

Foram lidos o handoff `JRC_Service_Desk_Projeto_Completo_DEV.docx`, a matriz
`JRC_Conversas_Matriz_Perfis_e_Permissoes.docx` e as 22 imagens PNG do pacote original.
As imagens foram inspecionadas visualmente em folhas de contato fora da raiz do projeto.
Não foram copiadas imagens com registros demonstrativos para a aplicação.

## Mapa das referências

| Imagem | Hierarquia aproveitada | Implementação CP3 |
|---|---|---|
| 01 Dashboard | Cinco cards, três painéis analíticos, recentes, tarefas e atalhos | OverviewView; cards sem números e painéis sem séries. |
| 02 Lista | Barra de busca/filtros, abas, tabela, paginação e prévia lateral | TicketListView; resultados aguardam API. |
| 03 Geral | Cliente/contexto, assunto, descrição, anexos e resumo | Etapa 1; unidade separada da empresa-cliente; anexos indisponíveis. |
| 04 Classificação | Prioridade/categoria/fila/responsável/status | Etapa 2; opções do backend, sem seeds no frontend. |
| 05 Relacionamentos | Contrato, serviço, ativo e outros registros | Etapa 3; campos indisponíveis, sem criar vínculo por texto. |
| 06 Revisão | Resumo, revisão e criação | Etapa 4; não confirma SLA, cobertura ou persistência. |
| 07 Workspace | Abas centrais, detalhes laterais, ações | TicketDetailView e estrutura de edição; ações bloqueadas. |
| 08 Minha fila | Cards, lista pessoal, próxima ação | Mesmo componente de lista, filtro mine server-side proposto; assumir indisponível. |
| 09 Filas/equipes | Listagem e detalhe de configuração | CatalogView, responsáveis separados; não implementa roteamento/capacidade. |
| 10 SLA | Políticas, marcos, calendário | Estrutura referencial; sem calculador, prazo fictício ou alteração no SLA de Conversas. |
| 11 Catálogo | Serviços/categorias/cobertura | Lista, colunas, painéis e abas de estrutura. |
| 12 Conhecimento | Artigos/categorias/publicação | Estrutura; Help Center intacto e publicação indisponível. |
| 13 Aprovações | Solicitações, responsáveis, histórico | Estrutura sem aprovar/rejeitar de verdade. |
| 14 Problemas | Registros, relações e solução | Estrutura, sem criar backend paralelo. |
| 15 Mudanças | Tipo, status, agenda, aprovações | Estrutura; agenda/execução indisponíveis. |
| 16 Ativos | Inventário e vínculos | Estrutura; importação e cadastro bloqueados. |
| 17 Contratos | Condições aplicadas, serviços e cobertura | Fronteira externa + snapshots, não um ERP nem dados financeiros inventados. |
| 18 Automações | Gatilhos, regras, versões/histórico | Estrutura; sem ativar/simular backend. |
| 19 Pesquisas | Instrumentos e resultados | Estrutura sem respostas, nota, CSAT/NPS/CES fictício. |
| 20 Relatórios | Filtros, análise e exportação | Estrutura indisponível; nenhum gráfico/export real. |
| 21 Configurações | Categorias/status/prioridades e regras | Cards + cadastros operacionais, unidades e operadoras da arquitetura aprovada. |
| 22 Portal | Identidade e experiência externa | Não implementado; aviso da fronteira, sem navegação externa. |

## Adaptações deliberadas

Nomes/cores operacionais e registros das imagens não foram usados como dados padrão.
O JRC mantém seu Dashboard, sidebar e design system. Botões, inputs, selects, banners,
tabelas, abas, paginação e loaders são os componentes nativos; somente os agrupamentos
e estados específicos do módulo foram criados. Os tokens CSS foram conferidos em
`theme/colors.js` e todos os seletores locais estão sob `.jrc-service-desk-root`.

NICO permanece o copiloto existente, não foi criado outro motor chamado Brain.
A navegação complementar evita reorganizar itens antigos da sidebar. Em tablet/mobile,
a barra interna passa a navegação horizontal e os painéis viram uma coluna.
As tabelas usam rolagem horizontal, sem alterar o layout global.

Os cards e painéis reproduzem hierarquia e espaçamento adaptados, não os valores de exemplo.
As telas complementares são esquemas distintos no mesmo componente configurado por tela,
não cópias de uma aplicação auxiliar.

**Revisão visual do Vue compilado em navegador nativo permanece pendente.** A inspeção das
referências e da estrutura do código não equivale a um teste de renderização ou fidelidade
pixel a pixel. Confirmar desktop/tablet/mobile, temas claro/escuro, textos longos e teclado
no ambiente Docker/local correto.
