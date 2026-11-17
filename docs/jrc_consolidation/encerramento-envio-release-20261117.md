# Encerramento de chamados — correção do envio pela interface

Produto: `d564cc3799b70c95ed933964bd80b8a6e8dbcb83`.
Branch: `codex/chamados-projetos-encerramento-envio-20261117`.
Base funcional: `688626104ca89001a74da142d121610509254025`, confirmada no HTML
público do aplicativo no início da tarefa. Inclui o encerramento sem requisitos
extras da ADR0005 e todas as correções anteriores de chamados, projetos,
propostas e mensagens. O commit posterior de evidências altera documentação;
a imagem corresponde ao SHA funcional acima.

## Problema corrigido

O formulário enviava a intenção `operational_closure`, mas a lista de campos
aceitos por `serviceDeskLifecycleClient` a rejeitava antes do POST. Por isso a
interface exibia falha e oferecia recuperação mesmo sem enviar o comando ao
servidor. A alteração funcional admite esse campo oficial no cliente HTTP.

Dois testes do formulário usando o cliente HTTP real e um backend sintético
reproduziram a falha antes da correção: zero POSTs, com motivo vazio ou preenchido.
Depois da correção, ambos executaram resolução e encerramento, preservando
as chaves de idempotência e confirmando transição, chamado e ciclo por leituras
independentes. Esses cenários não substituem o aceite operacional em produção.

Continuam válidas as decisões da ADR0005: funcionários com acesso ao chamado
podem encerrá-lo sem aprovação, evidência, classificação, solução, papel extra
ou motivo obrigatório. O fechamento registra tempo real e alimenta os
indicadores. Metas, prazos e violações configurados são preservados. Quando
faltam metas ou calendário, o cálculo de cumprimento fica pendente; essa
ausência não impede encerrar nem produz um SLA fictício como cumprido.
Conta, unidade, autoria, idempotência e privacidade permanecem preservadas.

## Imagem publicada e verificada

```text
ghcr.io/claudiohideki/jrc-conversas-lab2:sha-d564cc3799b70c95ed933964bd80b8a6e8dbcb83
```

```text
ghcr.io/claudiohideki/jrc-conversas-lab2@sha256:ce988fd810f0a8040750af825f1266f42be8e0ea90e206e391c8d906201ab017
```

Digest e configuração consultados independentemente no GHCR por
`docker buildx imagetools inspect`, sem baixar camadas para o desktop.
Plataforma `linux/amd64` e label `org.opencontainers.image.revision`
conferidos contra o SHA funcional acima.

## Validação

- Local: 72 testes em três arquivos aprovados, incluindo os dois cenários
  reproduzidos com o cliente HTTP real. ESLint dos dois arquivos alterados sem
  erros; três avisos preexistentes de texto sintético no spec.
- [Integração 44151790739](https://github.com/ClaudioHideki/jrc-conversas-lab2/actions/runs/44151790739):
  aprovada no SHA exato com PostgreSQL e Redis descartáveis; gate de encerramento
  com 84 exemplos Rails e suíte principal com 1.303 exemplos sem falhas.
  Concorrência, custódia e schema aprovados; 144 arquivos/1619 testes
  Vue, compilação real e 24 cenários de navegador aprovados.
- [Build e publicação 44154762687](https://github.com/ClaudioHideki/jrc-conversas-lab2/actions/runs/44154762687):
  três jobs aprovados; regressões adicionais com 168 exemplos Rails e 77 testes
  Vue; gates puros preservados; 296 arquivos/2759 testes frontend;
  construção, revisão, plataforma e conteúdo da imagem conferidos. Aplicação e
  worker passaram nos smokes antes e depois da publicação por digest.

As suítes se sobrepõem; não somar suas contagens como um total único.
Os transportes e as identidades usados nos cenários são sintéticos.

## Aplicação e limites

No Compose do Dokploy, substituir a linha `image:` da base compartilhada pela
referência por digest acima, salvar e implantar. Aguardar a conclusão e recarregar
a interface com `Ctrl+Shift+R`. Aplicação e worker devem usar a mesma versão.

Nenhuma migration nova, mudança de política/snapshot, alteração de credenciais,
envio real, backup, dump, restore ou implantação em produção foi executado neste
incremento. Sem merge em main. A publicação da imagem e o aceite operacional
após sua aplicação no ambiente da empresa são etapas distintas.
