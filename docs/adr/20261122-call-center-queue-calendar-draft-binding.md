# Vínculo interno entre fila e calendário

Status: implementação candidata; execução Rails e Chrome do novo SHA obrigatória.

O catálogo por unidade foi validado no produtor `369e7351746d5bb76e96a7bc9de767c86c2cba8e`. A seção6 dos dois Word exige calendários reutilizáveis e vínculos/impactos. Este incremento cobre somente a associação interna às filas nativas existentes. Números, URAs e impacto no fornecedor permanecem pendentes.

O vínculo ocupa uma chave tipada e reservada no JSONB da fila existente. Não cria fila, unidade, calendário ou cadastro paralelo. Cada operação fixa uma identidade de solicitação, a cópia exata do calendário revisado, seu digest canônico e o escopo nativo de conta/empresa/unidade/fila. O direito configure e a cobertura são recarregados depois da espera pelo mutex de Account. Revisões atuais da fila e da unidade do calendário são exigidas antes da escrita.

Uma alteração posterior no catálogo não modifica a cópia vinculada. A consulta sinaliza a divergência. Uma substituição exige carregar e revisar as configurações atuais; o antes/depois permanece na auditoria nativa. Trata-se de snapshot de configuração interna auditado, sem alegação de versão publicada ou de aplicação no PABX.

Há uma associação corrente por fila, evitando calendários locais concorrentes silenciosos. A mesma identidade só recupera a mesma solicitação integral. Mudança do conteúdo com a mesma chave recebe409. A resposta é capturada dentro da transação. Escritas genéricas não aceitam a chave reservada e preservam apenas essa chave ao substituir outros settings, mantendo a semântica legada. O modelo rejeita descarte e transferência silenciosa do vínculo entre unidades. Os tokens anteriores de registros permanecem inalterados; o novo digest de conteúdo reutiliza sua canonicalização sem mudar o algoritmo existente.

O popup preserva o contexto, mostra candidatos autorizados separadamente dos vínculos, permite comparação com o snapshot anterior e exige consentimento explícito. Conta, unidade, perfil ou permissão alterados descartam dados privados e respostas tardias. Resultado incerto mantém a solicitação para recuperação manual idempotente; conflito exige nova leitura e revisão. Não há repetição automática.

Impacto externo é `unknown`, nunca zero inferido. Salvar não cria Command, não chama fornecedor, não publica e não confirma aplicação. Nenhum grant, migration histórica, SQL, dependência, workflow ou infraestrutura foi alterado por esta decisão.

Aceite exige requisições autenticadas com banco sintético real, conflitos, reexecução, auditoria, isolamento e retirada de autoridade durante espera PostgreSQL; testes Vue direcionados e os mesmos244cenários Chrome, ampliados com criação do vínculo,409/revisão, recarga, snapshot preservado após edição do catálogo, paginação20/1 e negações. Capturas em1440/390claro/escuro exigem revisão real. Os39testes locais incluem10anteriores e usam transporte substituído; não substituem esse aceite.
