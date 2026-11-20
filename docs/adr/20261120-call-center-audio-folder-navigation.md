# Navegação autorizada de pastas institucionais — 20/11/2026

Complementa a decisão por unidade; não cria cadastro, grant ou operação externa. As figuras 6 e 16 exigem organização hierárquica. A fundação mostrava a pasta atual e um retorno; o próximo incremento apresenta o caminho completo com os mesmos identificadores nativos.

A consulta recebe a relação já autorizada pelo controlador, fixa conta/unidade da pasta selecionada e percorre apenas esses registros em uma consulta recursiva PostgreSQL. Não recebe conta, unidade ou SQL do cliente para conceder acesso. Ciclo retorna erro; um ancestral ausente do escopo resulta em não encontrado, sem caminho parcial ou nome oculto. Não altera árvore, revisões, auditoria ou migrations.

O navegador permite voltar a qualquer ancestral autorizado e diferencia a pasta atual. O nome máximo de120caracteres, inclusive sem espaços, deve caber em390px. Respostas antigas de ancestrais são descartadas ao trocar conta, usuário ou unidade.

Negativas conhecidas da API ao abrir, listar destinos ou salvar invalidam respostas pendentes e limpam lista, caminho e rascunho privado. Uma resposta tardia anterior à negativa não pode repovoar o painel. Falhas transitórias comuns continuam preservando o rascunho e não provocam repetição automática.

Validação preparada: seis exemplos de serviço com PostgreSQL real (incluindo13níveis em uma consulta, conta/unidade negadas e ciclo sintético), um cenário de API, sete casos Vue adicionais e extensão dos quatro cenários Chrome nativos existentes. Exigir a negativa real de operador após abrir o popup, sem mudar permissões reais. Nenhum resultado é aceito apenas pela análise estática.

As220combinações Chrome são preservadas. Arquivos, versões, player, scanner, vínculos, gravação e Nico não fazem parte deste incremento e continuam pendentes; as figuras completas não estão concluídas.
