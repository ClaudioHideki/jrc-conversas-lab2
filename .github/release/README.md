# Gate de liberação da candidata de runtime

Produto imutável: cabfac0807404295f8405fadbe2255239c0c6719.
Branch do produto: codex/runtime-alpine324-numbering-20261112.
Base consolidada preservada: cad427d400d824fc1fdc06c1c1079f324e7f3f6c.

Esta branch contém somente infraestrutura de verificação adicional. O checkout do produto é separado e fixado; nenhum arquivo desta infraestrutura é sobreposto ao produto.

O gate exige a execução nativa completa do próprio SHA novo, suas 36 identidades lógicas, relatórios JSON positivos sem falhas, pendências ou erros externos, provas fresh/upgrade/idempotência/schema, MFA, concorrência, regressões incorporadas, frontend e hashes de todos os artefatos. Os resultados anteriores de cad427d4 não substituem os resultados desta candidata.

Ruby 3.4.12p148 e Node 24.22.3 foram declarados no produto. As imagens-base oficiais Alpine 3.24 são fixadas por digest. O novo contrato preserva versões de gems, pnpm-lock, migrations, fontes funcionais e imagem independente NICO, com uma única exceção explicitamente revisada: a alocação de protocolo de Backoffice detectada pelo teste de escala existente. O hash do modelo e seus quatro testes de regressão é exigido pelo contrato. A prova anterior à correção falha de forma intencional; a prova posterior e a CI final são registradas separadamente.

O teste de compatibilidade nativa executa Rails, bibliotecas nativas, PDF com DejaVu, OCR real, XLSX e um processo Sidekiq real em serviços sintéticos descartáveis Ubuntu. Isso não homologa ABI musl nem a imagem Alpine.

## Próxima operação, sujeita a autorização específica

Uma única tentativa de build Docker linux/amd64 em runner GitHub descartável, checkout exato do produto, sem GHCR/deploy/main/Compose. Guardas devem confirmar pelo menos 5 GiB de RAM disponível e 3 GiB de disco antes de começar, monitorando desde o início e interrompendo somente os processos desta tentativa ao atingir as reservas aprovadas. Sem builds simultâneos.

A guarda original foi preservada e só autoriza a antiga branch A–G. Portanto não pode ser reutilizada para o novo SHA sem uma adaptação explícita de infraestrutura. A operação futura deverá fixar separadamente o SHA de infraestrutura e cabfac0807404295f8405fadbe2255239c0c6719, comprovar os dois checkouts e testar a autorização e a parada por recursos antes de qualquer build. Não será removida nem enfraquecida a guarda original. Reservas existentes: disco 750.000.000 bytes e RAM 750 MiB; monitoramento a cada 0,5 segundo, interrompendo apenas o cliente e builder exclusivos deste job.

Após build autorizado: conferir versões reais de Alpine/Ruby/Node, bibliotecas ELF/SSL/C++, gems nativas, fontes regulares/negrito, PDF/XLSX/OCR, assets/CSS recém-compilados e todos os módulos incorporados. Subir Rails e Sidekiq da mesma imagem local do runner, em rede/serviços sintéticos isolados, sem chamadas externas ou dados reais. Registrar ID/digest local, logs e smoke tests. Não publicar, etiquetar latest ou alterar ambientes existentes.

A compatibilidade Alpine, a compilação de assets e a homologação visual completa permanecem pendentes até essa autorização e execução. DocuSign demo, scanner externo e canais reais não são homologados por estes testes.

Esta infraestrutura não contém caminho de construção de imagem, publicação ou deploy. O resultado aprovado significa somente que a candidata pode ser apresentada para autorização de build protegido.
