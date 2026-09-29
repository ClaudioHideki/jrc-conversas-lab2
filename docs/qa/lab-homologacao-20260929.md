# Correções de homologação LAB — 29/09/2026

Branch: `codex/lab-homologacao-20260929`. Base preservada: `e2bdf2ad4c9e695ce458d03a65e6d1e50da34e7d`, consolidando QR/Broker, CRM/softphone e Service Desk R2. O checkout foi reutilizado limpo; o nome da pasta menciona Projetos/GoPure, mas nenhum desses candidatos foi integrado.

Imagem associada à base: `ghcr.io/claudiohideki/jrc-conversas-nico-v12-2-7-comercial-integrado:sha-e2bdf2ad4c9e695ce458d03a65e6d1e50da34e7d`, digest `sha256:c316dad3b6782da7a60b58b6aacfc6383176b8e89941b6ed9dae14f349247584`. A imagem efetivamente em execução no LAB não foi inspecionada no servidor nesta rodada.

## Causas comprovadas e correções

### Service Desk

O item de administração estrutural já era produzido em `menuItems` mediante contexto autorizado do backend, mas `menuSections` não o incluía em seção alguma. Agora ele é incluído em Administração, sem conceder acesso por papel. A navegação operacional continua independente. O botão Novo chamado na listagem agora observa `units[].permissions.create_ticket`, como a Visão geral já fazia; não promete ação recusada pelo guard/API.

A disponibilidade continua exigindo flag, vínculo ativo e capabilities/policies. Sem estado inicial configurado, a API pode legitimamente negar criação. A inicialização anterior beneficiou Thiago (AccountUser 15), não todos os usuários. Não foram alterados RBAC, UnitMembership, flags, migrations ou dados do LAB.

### Contraste de todo o sidebar

A configuração Tailwind substitui a paleta padrão. `text-blue-200` usado pelo componente compartilhado dos grupos não existe nessa configuração; por isso Times/Etiquetas e seus ícones/setas herdavam a cor do contexto. Também havia uso de tokens neutros do tema claro em superfícies permanentemente azuis, incluindo ordenação, estados vazios e indicador de rolagem. Links de subitens não possuíam cor normal explícita no próprio link.

Foram adicionados tokens `sidebar.surface/foreground/secondary/muted/active` em `theme/colors.js`, aplicados exclusivamente aos componentes do sidebar, incluindo popover recolhido. Textos principais, secundários, títulos e setas usam cores claras, independentes do tema geral. As cores de fundo das etiquetas/VNodes não são alteradas. O destaque selecionado permanece exatamente `#087cf0`; hierarquia principal/subitem mantida. Nome e e-mail preservam os dados reais. Na sessão Claudio inspecionada o nome já estava branco; não se atribui a ela o defeito de outra sessão.

A scrollbar só do nav usa faixa azul, thumb discreto e hover mais claro, com propriedades padrão e WebKit. Firefox tem fallback CSS padrão; não houve execução visual em Firefox. Nenhuma cor branca global nem mudança de scrollbar global.

### CRM → Funil

Defeitos reproduzidos no código/testes: Todos os Funis (`pipeline_id=null`) limpava as colunas e retornava; falhas na consulta de pipelines eram absorvidas; carregamento de motivos de perda bloqueava a inicialização; carregamentos concorrentes podiam encerrar loading cedo e respostas antigas sobrescrever filtros novos. Os filtros Atrasados/Sem próxima atividade não eram aplicados pelo endpoint. Sem etapas/oportunidades faltava estado vazio explícito.

A consulta agora busca etapas dos funis autorizados, carrega etapas/negócios de forma conjunta, descarta respostas obsoletas, aplica os dois filtros sobre os registros retornados, mostra erros e permite tentar novamente. Carrega motivos somente ao mover para etapa perdida; mantém confirmação e rollback. Reconecta drag-end, não esconde etapas de perda e garante altura/overflow mínimos. Nova oportunidade mantém sua rota existente.

Não foi possível determinar os dados/permissões exatos do Thiago no LAB a partir da sessão disponível de Claudio. Os defeitos corrigidos foram reproduzidos localmente; não se afirma que todos eram a causa simultânea da captura.

## Auditoria de navegação

Inventário extraído do próprio `Sidebar.vue` com cenários de administrador, agente, autorização estrutural e flags desativadas. Arquivo: [matriz de navegação](lab-homologacao-20260929-menu.csv). Inclui rotas, componentes, metadados de permissão, guards e referências estáticas de dados/handlers. Times/etiquetas/filtros dinâmicos usam representantes sintéticos; não enumeram registros reais dos tenants.

105 entradas distintas. Todas as rotas enumeradas foram localizadas e os componentes referenciados existem. Isso é verificação estrutural, não prova que 105 jornadas foram clicadas no LAB. API e botões delegados exigem homologação manual quando indicado.

Resultados: 3 PASSOU (escopo local: Service Desk operacional/estrutural e Funil), 1 FALHOU (Atividades CRM), 1 BLOQUEADO POR PERMISSÃO — ESPERADO (CRM na sessão Claudio), 100 PENDENTE DE HOMOLOGAÇÃO MANUAL. Os três PASSOU ainda devem ser repetidos com a nova imagem no LAB.

### Falhas/controles pendentes preexistentes

- CRM/Atividades: Executar, Editar e Iniciar ação não possuem handler/rota em `ActivitiesIndex.vue`. Concluir e Reagendar possuem implementação. Não foram inventados fluxos novos.
- WhatsApp Calling: Gerar resumo com IA sem handler em `WhatsAppCallingPage.vue`. Tela acessada por atalhos/contexto, não uma entrada própria dos 105 itens desta matriz.
- Service Desk: exportação, próximo chamado e telas de referência/ações marcadas como pendentes continuam placeholders deliberados. A faixa de candidato não equivale a homologação concluída.
- Telefonia, campanhas, envio de mensagens, NICO e integrações externas não receberam operações reais nesta auditoria; nenhuma ligação/envio/DELETE real foi disparado para testar controles.

## Validações

- Vitest: 468 testes, 27 arquivos aprovados, incluindo autenticação Service Desk, autorização/rotas/sessão, novos testes de navegação estrutural, disponibilidade de criação, contraste/etiquetas, filtros/carregamentos concorrentes e componentes do Funil.
- RSpec em Docker, PostgreSQL/Redis isolados e descartáveis: 405 exemplos, zero falhas. Requests, serviços, policies e models Service Desk, inicialização Super Admin, feature flag e CRM. Grupo `sd_concurrency` excluído nesta execução; não se declara validação concorrente completa.
- `RAILS_ENV=test db:prepare` e `zeitwerk:check` aprovados. Não há novas migrations nesta correção e nenhuma migration no LAB.
- Preview local usando componentes reais com dados sintéticos: Funil vazio, preenchido e erro; perfil expandido/recolhido; grupos/ícones/chevrons claros, hover branco, item selecionado azul e tema claro/escuro. Popover do menu recolhido conferido.
- Paleta normal sobre azul: foreground/secondary/muted com contraste calculado >=4,5:1. O azul ativo preexistente foi preservado; não se declara certificação de acessibilidade de todos os estados.
- Build frontend final: aprovado em 2m11s; `git diff --check`: aprovado.
- ESLint comparado à base nos arquivos alterados, normalizando CRLF: 120 erros preexistentes → 111 remanescentes e 6 avisos; nenhum arquivo aumentou o total de erros. Os cinco novos arquivos de testes passaram sem erros/avisos. Ajustes de formatação restritos aos trechos desta rodada. Dívida global histórica de RuboCop/ESLint não foi corrigida. Warnings de i18n nos fixtures e sourcemap ausente de dependência não impediram os testes.

## Homologação restante após atualização manual do LAB

1. Conferir digest da imagem implantada e renovar sessão/assets.
2. Admin estrutural: ver administração; sem vínculo operacional não acessar chamados. Agente autorizado: chamados/minha fila; admin+agente: ambos. Sem vínculo/inativo/capability/flag: negar URL/API.
3. Configurar estado inicial e autorizações explicitamente, depois criar/editar/tratar chamado e validar releitura persistida, filas e equipes. Esta correção não cria essas concessões automaticamente.
4. Thiago: CRM com dados reais, seleção Todos/específico, responsável, busca, atrasados, nova oportunidade, mover etapa, perda e recarregar. Conferir requests/console da sessão dele.
5. Executar as jornadas pendentes da matriz com perfis e dados de homologação; repetir scrollbar em Chrome/Edge/Firefox e estados do sidebar.

Publicar imagem não realiza deploy. Não alterar Dokploy, Account ou banco; não iniciar Projetos/GoPure.
