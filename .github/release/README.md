# Gate de liberação isolado

Produto imutável: cad427d400d824fc1fdc06c1c1079f324e7f3f6c.
Run nativo: 43250764582, tentativa 1.

Esta branch contém somente infraestrutura. O caminho registrado ag-native-candidate.yml é usado apenas nesta branch para permitir dispatch sem editar a main. Não altera o workflow da candidata aprovada. O checkout do produto é separado e não recebe overlays.

O dispatch exige o SHA completo desta infraestrutura e o SHA do produto. O gate recupera os 44 artefatos, confere digests e conteúdo, 36 identidades exatas/5.546 exemplos, 46 jobs, migrations, JSON de frontend e concorrência, quatro suites HTTPS e assinaturas APT nos logs nativos. Recusa IDs herdados, expiração, relatórios ausentes e execução do build não autorizado.

Permissões somente contents:read e actions:read. Sem caminho de construção de imagem, publicação, deploy, credenciais de provedores ou alteração de orçamento. Um resultado verde autoriza apenas reconhecer a prova nativa; build e homologação de runtime/visual continuam separados.
