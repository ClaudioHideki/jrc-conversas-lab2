# Popups administrativos nativos do Call Center

Estado: decisão de implementação dentro do escopo 0–2 autorizado em 16/11/2026.

A Central mantém quinze entradas, os nomes dos dois Word e estados derivados de fontes locais. Nomes completos das classes de ícones são necessários para a extração Tailwind; a coleção Lucide instalada contém circle-pause e shuffle. O fixture deve usar o PostCSS/Tailwind real, sem substituir ícones ou estilos para aprovar os testes.

A edição de fila preserva o canal e a estratégia existentes. Filtros, página e aba usam parâmetros separados na URL e acompanham a volta à Central. Empresa e unidade corporativa são opções autorizadas, nunca concessões de acesso.

Team e TeamMember continuam sendo os cadastros nativos da conta. Dados da equipe e participantes têm ações de persistência separadas, identificadas ao usuário, usando as APIs nativas. Uma seleção de participantes ainda não salva impede concluir a edição dos dados sem revisão. Não há nova base, vínculo automático à distribuição, supervisão, monitoria ou ramal. O modelo Team não contém empresa/unidade nem hierarquia de supervisores; o painel não oferece edição global quando a cobertura corporativa é restrita. A autoridade existente dos endpoints do módulo de origem não é reescrita por esta tela.

QueueMembership mantém Participa e Supervisiona independentes. A validação nativa do Dialog é preservada e os campos rejeitados pela API são identificados. Salvamento em curso impede fechamento; falhas conservam o rascunho. A política ACW mantém os limites e transações nativos; não vira motor de automações por motivo.

A conexão cadastrada e a importação CDR não provam PABX online ou recurso publicado. Comandos remotos e recursos sem contrato continuam bloqueados. A Central de Aprovações mantém suas próprias políticas; nenhum fluxo ou alçada é ativado.

A matriz stages_0_2_review_20261116.json distingue funções locais, dependências externas e etapas 3–8. Resultados da CI e capturas precisam corresponder ao SHA efetivamente executado. Nenhuma existência de tela ou teste simulado fecha a homologação externa.

O popup de Permissões reutiliza CustomRoleModal, CustomRoleAPI e o store customRole existentes. O acesso depende de custom_roles, papel administrativo nativo e cobertura corporativa irrestrita. A seleção continua explícita: configurar o Call Center não concede publicação, monitoria ou outras capacidades automaticamente. A origem nativa mantém sua autoridade original. O Dialog usa contenção e rolagem já existentes, sem formulário externo envolvendo o formulário nativo; o submit propagado não pode acionar o salvamento genérico do painel.

A CI 43909947337 confirmou 383 exemplos Rails, 172 testes Vue e 32 de 40 cenários Chrome. Os oito timeouts ocorreram nos seletores de Unidade operacional e Fila em quatro projetos; os snapshots mostram os comboboxes e suas opções. A revisão usa papel e nome acessível exatos, verifica a seleção e mantém as asserções de persistência. Os resultados do novo checkpoint ainda precisam ser produzidos; essa correção não equivale a uma homologação já aprovada.
