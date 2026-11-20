# Recebimento privado de áudios institucionais por unidade

Status: direção técnica aceita no escopo autorizado; implementação candidata ainda depende da CI nativa e do Chrome no próprio SHA. Não representa aceite completo das figuras6/16.

## Contexto e limites

A biblioteca pertence à unidade operacional nativa e à cobertura corporativa atual, conforme decisão do usuário. Não é o catálogo de gravações de chamadas nem o catálogo de mídias de Campanhas. O checkpoint7dfccc8f comprovou somente pastas/caminhos e a limpeza da interface após acesso negado.

## Decisão

- Usar `AudioAsset` como identidade estável e `AudioVersion` como recibo imutável do arquivo exato. Renomear/mover na mesma unidade não altera o histórico. Não há operação de transferência entre contas/unidades nem API de exclusão.
- Reutilizar `ModulePolicy.configure?`, `AccessScope.units`, `CorporateCoverage` e o mutex nativo da Account. Recarregar usuário, vínculo, conta e fontes antes da gravação e depois do upload; IDs do cliente apenas selecionam dentro do escopo autorizado.
- Reutilizar o mecanismo de armazenamento próprio de `JrcBackoffice::PrivateBlob`, sem criar requests fictícias de Backoffice. Receber somente `UploadedFile`, identificar o cabeçalho real com Marcel, aplicar o limite nativo `MAXIMUM_FILE_UPLOAD_SIZE`, conferir os bytes armazenados e SHA-256. O limite existente por arquivo não define uma quota nova da biblioteca.
- Não criar attachment ActiveStorage/análise implícita. Vincular um blob novo à versão por FK. Bloquear redirects, proxies, representações, leituras e alterações assinadas pelo DiskController; assinaturas de URL não concedem acesso. Os payloads não retornam locators, IDs de blob, chaves de armazenamento ou correlatores privados.
- Proteger no PostgreSQL a origem, a sequência e a imutabilidade das versões, os bytes referenciados e o bloqueio de reaproveitamento como attachment público. Cada blob tem um único dono histórico. O SQLSTATE de bloqueio de purge é23503, preservando a retenção e a compatibilidade com o tratamento nativo de `ActiveStorage::Blob#purge` do Rails7.1.5.2; não desativar o guard.
- Compor o CAS nativo com a última versão exata. A chave idempotente pertence à conta/unidade/usuário; conferir o conteúdo exato e reautorizar também no replay. Aguardar a gravação atômica antes da resposta; compensar somente o blob novo sem referências da própria tentativa. Se a compensação for incerta, preservar os bytes e registrar apenas a classe do erro, sem limpeza global.
- Manter o criador na identidade User nativa, sem FK para o vínculo removível de AccountUser. A retirada do vínculo não apaga a autoria. A política global de exclusão/retenção não é redefinida nesta implementação.
- Reutilizar a auditoria nativa com escopo atual/histórico. Registrar versão/hash/origem sem filename, blob, conteúdo ou chaves do recibo. Manter logs de parâmetros filtrados.
- Usar Dialog nativo e revisão explícita. Preservar o mesmo File/FormData/chave após falha incerta, bloquear submissões concorrentes, conferir a identidade do recibo2xx e esquecer dados/respostas atrasadas após troca de contexto ou acesso negado. A interface oferece metadados, edição/movimentação, nova versão, busca/paginação e histórico.

## O que não foi concluído

Todo recibo permanece `not_verified`, sem prévia, download ou uso operacional. Marcel reconhece cabeçalho; não comprova codec, duração ou segurança do conteúdo. O critério do Word de rejeitar falha de codec antes da persistência de um áudio válido **não está aceito** por este incremento de quarentena privada. A próxima fase precisa de inspeção real, scanner e tratamento do resultado antes de liberar qualquer áudio. Não atribuir a testes de parser ou mocks uma homologação do scanner.

Também permanecem pendentes o player, metadados reais da mídia, vínculos/versionamento de publicação, gravação pelo navegador, Nico, operações em lote, quota e a composição visual completa da biblioteca/painel de detalhes das referências. Não apresentar duração, vínculo ou status ativo inventados. PABX continua sem contrato e sem comandos reais.

## Validação exigida

Migration aditiva20261120120000, oito anteriores preservadas, três fontes SQL/receipt fixadas por SHA-256; instalação, upgrade populado, idempotência, schema reload, FKs/guards, auditoria, CAS, compensação e concorrência reais. Acrescentar quatro Chrome aos220 existentes: arquivo inválido/válido, seis registros reais/página5, edição, versão, reload, escopo negado,390/1440 e claro/escuro. Manter todos os gates.

Os testes que escrevem arquivos exigem GitHub hosted, bancos sintéticos identificados, Redis loopback/15 e DiskService resolvido dentro de armazenamento temporário do próprio runner. O seed de Chrome verifica isso antes de criar dados. Nada é instalado, migrado ou compilado no Windows.

Referência técnica: [ActiveStorage Blob do Rails7.1.5.2](https://github.com/rails/rails/blob/v7.1.5.2/activestorage/app/models/active_storage/blob.rb#L285). A configuração real de armazenamento externo e suas ACLs não foi homologada nesta execução.
