# 0010 — Ciência por versão do Manual de Cultura

**Estado:** Aceita para implementação da candidata local (23/11/2026).

O percurso usa a conta existente do JRC e a rota independente `/portal/manual-de-cultura`. O portal de chamados compartilha somente a autenticação nativa e o padrão de transporte. A Universidade mantém seu link e seu componente.

A permissão vem do vínculo próprio do Manual e da cobertura organizacional ativa em conta, empresa e unidade. O papel nativo do JRC, por si só, não concede administração do Manual. A habilitação dos primeiros administradores é uma operação separada e auditada.

O público da versão corresponde às unidades selecionadas. A publicação associa os vínculos habilitados e uma habilitação posterior entra nas versões publicadas para aquela unidade. A confirmação atualiza a associação do próprio colaborador com timestamp do servidor. A chave única de vínculo e versão, a transação e o evento registrado uma vez protegem a repetição e a concorrência. A troca de versão preserva a anterior, inclusive os registros já feitos e os arquivos associados.

A notificação fica na seção **Confirmações recentes** do próprio painel administrativo. Ela consulta as ciências persistidas sob o mesmo escopo do relatório. O fluxo usa o padrão de fato persistente das aprovações, sem compartilhar a fila de avisos comerciais ou enviar mensagens externas.

PDF, PPTX e XLSX usam armazenamento privado e a verificação do scanner existente. Os arquivos só saem pelas rotas autorizadas do módulo. Os locators nativos do Active Storage não liberam os arquivos do Manual. A planilha é usada somente na administração e a aplicação da importação recalcula os vínculos selecionados a partir do original protegido.
