# Fontes Ubuntu efetivas no runner descartável do Call Center

## Evidência e causa

CI44493933103, SHA79ef66b0d421685be2dfbf30e867036ba2ff0859, job135456219598, foi cancelada pelo limite nativo de45minutos. A anotação do GitHub confirma o timeout.1335Rails distintos,16reexecuções de schema e662Vue passaram, com zero falhas/pendências/erros externos nos relatórios; frontend lint e Ruby lint passaram. O build de assets foi cancelado e bootstrap/168Chrome não executaram. Nenhum destes últimos gates é aprovado por herança.

Artefato14517850671, SHA-256f1db7a5bea28eea6020605e4d033255e513f04ef2932e5d6df172d18f4dc1e23,199215bytes, recuperado e verificado. Log sanitizado: SHA-256bf202a6ded4a83ae5037a453c3f0ed8016d277618924eb0f98df376b2ad00e81. A última homologação integral permanece a8c6c78d,164Chrome; exclusão de equipe e a correção do ciclo de imports ainda exigem a próxima prova real de navegador.

O helper anunciou archive.ubuntu.com por HTTPS e validou o metadata em19segundos, mas a imagem desse runner continha mirror+file:/etc/apt/apt-mirrors.txt com http://us-east-2.ec2.archive.ubuntu.com/ubuntu/. A substituição anterior não reconhecia o hostname regional. O APT efetivamente baixou46,3MB por esse HTTP em24min34s,31,4kB/s. A preparação completa consumiu25min26s. As assinaturas APT continuaram habilitadas; a exigência de transporte HTTPS efetivo não foi satisfeita nessa execução. Não se presume que outros runs tenham a mesma configuração regional.

## Correção delimitada

Preservam-se os três mirrors HTTPS aprovados, os testes das quatro suites, connect-timeout5/max-time10 do curl, ForceIPv4, retries2, timeouts20s do APT, pacotes, keyrings e componentes. O novo preparador stdlib lê apenas os arquivos nativos sources.list, *.list, *.sources e apt-mirrors*.txt sob /etc/apt. Reconhece o hostname EC2 regional e normaliza somente URLs Ubuntu para o mirror já escolhido.

Antes da primeira gravação, valida as fontes ativas efetivas, inclusive os arquivos mirror+file, exige noble/noble-updates/noble-backports/noble-security e recusa endpoint inesperado, plaintext residual, lista desconhecida/vazia, caminho fora de /etc/apt, URI com credencial/query/fragmento e opções que dispensem segurança. Não troca keyrings, suites ou componentes nem reescreve repositórios de terceiros. As recusas usam mensagens genéricas, sem conteúdo de arquivos ou credenciais.

O CLI exige Linux Ubuntu Noble, GitHub Actions, runner github-hosted e o repositório exato. A configuração temporária APT torna explícitos AllowInsecureRepositories=false, AllowDowngradeToInsecureRepositories=false e AllowUnauthenticated=false; apt-get update/install continuam obrigatórios e verificam as assinaturas. As mesmas opções persistem para o instalador nativo do Playwright nesse runner descartável.

24testes pequenos de fontes em fixtures passaram em Windows, sem APT/rede/configuração do host. Incluem reprodução da origem regional real, audit efetivo que recusa o caso antigo, quatro suites, preservação de keyrings/arquitetura/comentários/terceiros, formatos list/deb822, idempotência, rejeições e guard do CLI. Bash -n passou. Isso não equivale a executar APT/Linux ou a homologar o produto.

A única mudança no workflow é bash -n antes do helper. O limite45minutos, as168asserções Chrome, as matrizes, permissões, guards de memória/disco, JSONs positivos e zero falhas/pendências continuam intactos. A proposta65minutos preparada fora do código não foi aplicada. Uma auditoria dos20workflows confirmou os demais blobs idênticos ao checkout preservado; somente o workflow nativo de Call Center é acionável por este push, sem caminho de build Docker/publicação.

A ferramenta local de checkpoint admite somente os três caminhos de infraestrutura revisados com seus hashes exatos, além do workflow já permitido. Scripts desconhecidos, outros arquivos .github e novas migrations permanecem bloqueados. Nenhum dos23arquivos incompletos de formulários ACW ou do rascunho SQL externo entra neste checkpoint.

## Critério de conclusão

A próxima CI precisa provar em Linux as fontes efetivas HTTPS, quatro suites, update/install assinado, todos os gates nativos, build novo, bootstrap sem erros e168Chrome. Não haverá sucesso por ausência de relatório, cancelamento ou desativação de controles. Nenhuma operação em produção,5379, quatro contêineres originais, Docker/GHCR, merge, limpeza ou PABX é realizada.
