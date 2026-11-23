# Base verificada para a imagem de correção do Service Desk

Data: 2026-11-23. Preparação local; este registro não representa deploy.

## Última imagem oficial consultada

- Registry/repositório: `ghcr.io/claudiohideki/jrc-conversas-lab2`.
- Tag: `sha-ab6bba04749fc38276c6465968b9e757aa7f93c2`.
- Digest: `sha256:51eda0b109d240ed5a8491238065fc0bdee24c475deb9f6911e1fbeafe8c791b`.
- Revisão OCI e origem Git: `ab6bba04749fc38276c6465968b9e757aa7f93c2`.
- Branch de origem: `codex/abertura-chamados-agentes-20261119`.
- Criação OCI: 2026-11-19 17:39:43 UTC.
- Push concluído: 2026-11-19 17:43:42 UTC (14:43:42 em Brasília).
- Publicação e smokes aprovados no [workflow44577404793](https://github.com/ClaudioHideki/jrc-conversas-lab2/actions/runs/44577404793).
- Plataforma: `linux/amd64`.

Foram enumeradas 114 tags no GHCR, com leitura de manifests e metadados OCI.
A identificação foi cruzada com o histórico dos workflows oficiais, sem usar
uma suposição sobre `latest`. A API GitHub de pacotes não permitiu a listagem;
a conferência do registry foi feita diretamente pelos endpoints OCI do GHCR.

A tentativa posterior de `codex/nico-provider-usage-20261123`, revisão
`c500b0ae2c914ba2e27d3342c8db8c79f3be3f10`, falhou na conferência de componente,
antes da autenticação e do push. Não substitui a versão oficial acima e não
integra esta publicação do aplicativo.

## Comparação das três referências

- `origin/main`: `e6bd4cc9418b3522378a460bb97814b700f39123`, ancestral da imagem oficial.
- Base local: `b6cfb5725e931c2e810146d0544a205a6c2c88af`, descendente direta da
  origem oficial, com apenas documentação adicional.
- Não há diferenças funcionais entre a base local e a origem da imagem nas
  árvores app/config/db/lib/enterprise/public/script/docker e manifests de dependências.
- As correções locais de 23/11 foram aplicadas integralmente numa branch isolada
  `codex/abertura-chamados-403-release-20261123`, sem merge e sem alterar a árvore
  original de investigação.
- `cp4Cases.js` foi formatado e adequado ao lint existente: iteração de arrays,
  declaração do global nativo usado no teste e declarações separadas. Os mesmos
  casos e assertions são preservados. O feedback mantém as mesmas cores com uma
  condicional equivalente, compatível com as regras do projeto. O gate oficial
  examina o arquivo alterado inteiro; nenhuma regra foi desabilitada ou contornada.

Não existem divergências funcionais não resolvidas com a última imagem oficial.
Não há alteração de schema, migrations, lockfiles ou Dockerfile nesta correção.
As funcionalidades anteriores permanecem por ancestralidade, não por cópia seletiva.

## Escopo e validação

Aplicação de SLA publicado na criação autorizada, destinatários elegíveis de
outras equipes/filas, independência de padrões internos inválidos, exclusão de
destinatários com autenticação inativa e preservação de formulário após 403.
Gravação manual de SLA, Pundit, supervisão e isolamento continuam protegidos.

O [relatório funcional](service-desk-save-403-validacao-20261123.md) discrimina as
validações locais amplas e os 176 Rails/87 Vue da revalidação final. A publicação
deve validar novamente o SHA exato nos workflows oficiais, compilar a imagem
completa e executar os smokes antes e depois do push por digest.

## Autorizações e rollback

A preparação, construção e publicação da imagem foram autorizadas. O envio de
código Git exige autorização separada; não há autorização de merge ou deploy.
A tag nova deverá ser exclusiva do novo SHA, com conferência de ausência antes
do push. A tag e o digest anteriores permanecerão disponíveis para rollback.
Nenhum serviço, banco ou volume de produção é modificado nesta publicação.
