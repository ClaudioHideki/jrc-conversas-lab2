# Chamados e Projetos — imagem publicada em 17/11/2026

Produto: `a5d5e1a07374c2859912454be60797a2d121c9c8`.
Branch: `codex/chamados-projetos-20261117`.
Base funcional publicada mais recente no início da tarefa:
`d468beb8744856c4bcaa972ecde4d885b60ee432`, digest
`sha256:21dfe92cdde1b2e8c3da838681bec5684bc87261f9aef2d4e39df0510c5128d4`.
Preserva a retirada do filtro de segmentos, o popup de propostas e as
atualizações posteriores de mensagens, recibos e histórico.

## Comportamento entregue

- A abertura interna simplificada oferece empresa operadora, unidade e pessoas
  elegíveis na fila/equipe dessa unidade. O responsável escolhido é persistido,
  revalidado no servidor e incluído na verificação de idempotência e readback.
  A identidade do solicitante permanece a do usuário autenticado.
- Agentes habilitados em Projetos podem criar por padrão. Negação individual
  explícita e limitações de CustomRole continuam sendo respeitadas.
- Agentes só acessam projetos em que são responsáveis ou participantes, incluindo
  listagens, indicadores e acesso direto. Administradores nativos veem os projetos
  da conta. A visibilidade legada account não concede acesso a terceiros.
- A lista principal de chamados mostra abertos/aguardando. O botão ao lado de
  Chamados abre um popup paginado com fases terminais, acessando o mesmo escopo
  autorizado. O popup fecha por botão, Esc ou clique no fundo e permite abrir o detalhe.
- Resolvidos soma resolvidos e encerrados. Aguardando usa a fase waiting; ambos
  atualizam após mutações. A seleção de fase/status da lista não zera os demais
  cartões. Reabrir devolve o chamado à lista operacional.

## Imagem

Tag:

```text
ghcr.io/claudiohideki/jrc-conversas-lab2:sha-a5d5e1a07374c2859912454be60797a2d121c9c8
```

Referência por digest:

```text
ghcr.io/claudiohideki/jrc-conversas-lab2@sha256:7fbe9fc9c53a632f698c980ff4d534a3baa81a9b003b1df0f9c7827839a705c3
```

Manifesto lido independentemente no desktop por docker buildx imagetools inspect:
Docker v2, tamanho 3042; plataforma linux/amd64 e label
org.opencontainers.image.revision iguais ao SHA do produto. Nenhuma camada nova
foi baixada para o desktop.

## Validação

- [Integração 44095082428](https://github.com/ClaudioHideki/jrc-conversas-lab2/actions/runs/44095082428):
  aprovada no SHA exato, PostgreSQL e Redis descartáveis; suíte principal com 1299
  exemplos Rails sem falhas, gates de concorrência e custódia aprovados,
  144 arquivos/1615 testes Vue, build real e 24 cenários de navegador aprovados.
- [Build 44098840211](https://github.com/ClaudioHideki/jrc-conversas-lab2/actions/runs/44098840211):
  três jobs aprovados, gate adicional com 168 exemplos Rails, verificações puras com 28/10/92
  execuções sem falhas, 296 arquivos/2755 testes frontend, construção da imagem,
  conferência dos arquivos/revisão e smokes da aplicação e worker antes/depois
  da publicação por digest aprovados. O workflow exige a integração do mesmo SHA.
- Local: 97 testes de componentes/navegação aprovados; ESLint sem erros. Ruby foi
  validado no runner, pois o daemon Docker local estava indisponível.

As suítes se sobrepõem; suas contagens não constituem um total único.
Os cenários usam identidades e transportes sintéticos.

## Limites

Nenhuma migration nova, alteração de credenciais, envio real, backup, dump ou
restore foi executado nesta tarefa. A imagem está publicada; não houve merge em
main nem implantação no servidor de produção. O aceite operacional da interface
no ambiente da empresa depende da aplicação da imagem.
