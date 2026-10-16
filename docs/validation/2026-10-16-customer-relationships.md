# Customer360: mapa de relações — evidência local

Na Visão 360 da empresa, o botão de carregar relações consulta um endpoint autorizado e mostra grupos de registros reais, contagem distinta e amostra dos dez mais recentes. Abrir um grupo usa as abas existentes. Não há inferência de IA, outro banco, ativação de bot ou alteração de registros.

O endpoint usa a empresa limitada ao Account, cobertura corporativa e scopes Customer360 de caixas, CRM e módulos. A projeção não contém corpo de mensagens, notas, documentos ou dados de integração. Capacidades ausentes são omitidas; tarefa sem permissão não vira um falso zero. Troca de Account/empresa e desmontagem invalidam respostas atrasadas.

Evidência: RED de método ausente, rota ausente, amostra duplicada por join e tarefa sem permissão; GREEN com **15 exemplos Rails** (serviço, timeline e requisição), **8 testes de interface** (componente e contexto Account). Títulos escapados, erro/recuperação, contagem e troca somente de Account com o mesmo ID numérico cobertos. Revisão independente sem achados Critical/Important; ajuste Minor de tarefas reproduzido e corrigido.

RuboCop dos quatro arquivos novos/Visibility: sem infrações. Customer360 herdado conserva 19 infrações preexistentes fora do método adicionado, que não foi apontado pelo lint. ESLint dos cinco arquivos de interface: sem erros; dez avisos preexistentes de texto literal em CompanyPage. Diff sem erros de whitespace.

Ruling: a API existente responde 401 quando o módulo de cadastro está desabilitado. O teste preserva essa convenção; não muda a semântica de autorização global.

Limites: projeção agrupada, sem canvas de física/zoom. Navegação integrada foi conferida em código e emissão do componente; ainda falta homologação visual no novo servidor. O manifesto de composição/guards será regenerado no fechamento consolidado porque a rota mudou. Sem alterações de schema, Compose, ENV, imagem, push ou produção.
