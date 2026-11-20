# Filtros de origem e formato da versão atual

Estado: preparado; validação nativa, Vue e Chrome ainda pendentes.

As figuras 6/16 exigem filtros da biblioteca sem perder o contexto. O índice existente passa a aceitar `source_kind` e `content_type`, ambos opcionais e limitados aos valores canônicos já existentes. Valores malformados são rejeitados com erro explícito; não se retorna silenciosamente uma lista sem filtro.

A relação vem de `AudioLibraryAccess`, depois de validar a unidade e a pasta. O helper não concede autoridade e não recebe IDs para ampliar o escopo. Sua subconsulta escolhe uma única versão mais recente por ativo autorizado e aplica os critérios a essa versão. Uma origem antiga não faz o ativo reaparecer, nem há duplicação por versões anteriores. Busca, contagem e paginação continuam no servidor.

A interface mantém unidade, pasta, nome, origem, formato e página na rota. Aplicar critérios ou removê-los volta à primeira página. A limpeza conserva os demais parâmetros e remove também o texto da busca. Respostas anteriores são invalidadas na troca dos filtros, junto com detalhes e histórico privados. A interface não filtra somente os itens da página carregada.

Foram preparados dez cenários HTTP nativos e quatro Vue. Os quatro cenários Chrome de captura existentes passam a comprovar o filtro com um OGG/Opus realmente gravado pelo dispositivo sintético, persistência após recarga, ausência de resultado para WAV e remoção dos filtros mantendo a unidade. Os 236 cenários continuam obrigatórios, sem reduzir os anteriores. Ainda não há resultado desse incremento.

Formato canônico não é promessa de codec aceito no PABX. WebM pode ser consultado como formato de versões legadas já admitidas pelo schema; isso não amplia a lista de formatos de importação. O filtro de tipo de uso depende do cadastro real de vínculos; o status operacional depende de seu estado nativo. Nenhum deles é simulado pela origem ou pelo resultado do scanner. Publicação, Nico, usos e exclusão segura continuam requisitos separados.

Não há migration, SQL histórico, nova permissão ou novo endpoint. As regras existentes de conta, unidade, configuração e acesso aos bytes são preservadas.
