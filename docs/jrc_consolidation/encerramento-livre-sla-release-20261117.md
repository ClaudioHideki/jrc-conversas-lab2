# Encerramento manual de chamados — imagem publicada em 17/11/2026

Produto: `688626104ca89001a74da142d121610509254025`.
Branch: `codex/chamados-projetos-encerramento-20261117`.
Base funcional: `a5d5e1a07374c2859912454be60797a2d121c9c8`, imagem mais
recente publicada no início deste incremento. Preserva destinatários de chamados,
projetos por responsável/participante, criação por agentes, indicadores e popup
de encerrados, além das alterações anteriores de propostas e mensagens.

## Problema e comportamento entregue

O encerramento manual de um chamado antigo era bloqueado porque sua política
exigia metas e calendário de SLA ausentes. Agora funcionários com acesso ao
chamado e à unidade operacional, incluindo administradores, podem encerrá-lo sem
permissão extra de fechamento, leitura de notas/SLA/histórico, papel restritivo
da política, aprovação, evidências, classificação, solução ou motivo obrigatório.

A intenção de encerramento manual é explícita. Executores automáticos e portais
de clientes não recebem essa ampliação. Continuam válidos o escopo de conta e
unidade, a autoria real, as etapas do ciclo, a versão esperada, o lock,
a idempotência, a auditoria e a confirmação do resultado. Permitir encerrar não
libera notas nem o histórico privado de terceiros. O autor consegue confirmar
seu próprio recibo manual. Uma falha na captura opcional do NICO depois da
transação não converte um encerramento já confirmado em erro para o operador.

Com SLA configurado, os relógios de atendimento e resolução são concluídos no
instante real, preservando metas, prazos, pausas e violações. Uma primeira
resposta que não ocorreu não é inventada. Sem configuração válida, o fechamento
prossegue e registra tempo real e cálculo pendente, sem fabricar cumprimento.
Os indicadores de resolvidos/encerrados e a cobertura de SLA usam esses fatos.
Não foram reescritos snapshots nem políticas históricas.

## Imagem verificada

```text
ghcr.io/claudiohideki/jrc-conversas-lab2:sha-688626104ca89001a74da142d121610509254025
```

```text
ghcr.io/claudiohideki/jrc-conversas-lab2@sha256:53b9ebc6f5938e40c3294d4487b894474b9ced88464cd707a60a1794957ee57a
```

Manifesto e configuração conferidos independentemente no desktop por
`docker buildx imagetools inspect`: digest acima, plataforma `linux/amd64` e
label `org.opencontainers.image.revision` igual ao SHA do produto. Somente
metadados foram consultados; nenhuma camada foi baixada para o desktop.

## Evidências

- [Integração 44139348538](https://github.com/ClaudioHideki/jrc-conversas-lab2/actions/runs/44139348538):
  aprovada no SHA exato, com PostgreSQL e Redis descartáveis. Gate focado com 84
  exemplos Rails; suíte principal com 1.303 exemplos sem falhas; concorrência,
  custódia e schema aprovados. 144 arquivos/1.617 testes Vue, compilação real e
  24 cenários de navegador aprovados.
- [Build e publicação 44142694078](https://github.com/ClaudioHideki/jrc-conversas-lab2/actions/runs/44142694078):
  três jobs aprovados; gate adicional com 168 exemplos Rails e 77 testes de
  interface. Gates puros preservados, 296 arquivos/2757 testes frontend,
  construção da imagem, conferência do produto/revisão/plataforma e smokes da
  aplicação e worker antes/depois da publicação por digest aprovados. O workflow
  exige integração aprovada no mesmo SHA.
- Local: 29 testes Vue aprovados e ESLint sem erros nos fontes alterados. Ruby
  foi validado no runner. O daemon Docker local permaneceu indisponível.

As suítes se sobrepõem; suas contagens não devem ser somadas como um total único.
Transportes e identidades dos cenários são sintéticos.

## Aplicação e limites

Substituir somente a referência `image:` da base compartilhada do Compose do
Dokploy pela referência por digest acima, salvar e implantar. Aguardar a
conclusão e recarregar a interface com `Ctrl+Shift+R`. Aplicação e worker devem
usar a mesma versão. O aceite em produção exige verificar um chamado do ambiente.

Nenhuma migration nova, alteração de credenciais, envio real, backup, dump,
restore ou implantação em produção foi executado neste incremento. A imagem foi
publicada sem merge em main. O commit posterior de evidências altera somente
documentação; a imagem corresponde ao SHA do produto indicado acima.
