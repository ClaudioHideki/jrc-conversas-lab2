# Identidade numérica estável no vínculo nativo de equipe

## Problema e correção em preparação

O controller nativo valida os IDs por to_i e compara IDs persistidos numéricos com user_ids da requisição sem a mesma conversão ao calcular inclusões/remoções. Uma substituição com strings numéricas pode tratar um participante selecionado como retirado e perder sua herança funcional/corporativa. A revisão estática foi registrada anteriormente; os novos cenários HTTP precisam comprovar o candidato no runtime nativo.

A correção proposta limita-se às duas diferenças de conjuntos já existentes: aplicar a mesma conversão numérica usada pela validação nativa, preservando todas as validações, políticas, lock e guards Enterprise. Nenhuma concessão nova, alteração no parser de entrada, novo cadastro ou alteração de schema.

Seis cenários HTTP preparados: substituição sem mudança preserva o ID do vínculo e fontes atuais; substituição mista preserva participantes selecionados; inclusão aditiva idempotente; usuário de outra conta negado; compatibilidade com Call Center desabilitado; remoção explícita mantém fontes armazenadas inativas e elegibilidade individual sem continuar concedendo autoridade por equipe. As permissões são consultadas com políticas novas após cada operação, sem cache de decisão anterior.

## Limites

Este incremento não implementa a confirmação de retirada indireta do último agente de fila: essa prévia completa ainda precisa considerar herança funcional, cobertura corporativa, outras equipes e operação mista sem mutações temporárias que disparem caches. Os cenários novos não criam filas e não simulam aprovação do gestor. Mantém-se a decisão de confirmação explícita com revisão e auditoria; sem comandos PABX nem operações reais.

Pendente: testes Rails, lint incremental e regressões do próprioSHA. Não herda o aceite da CI090a1dac e não conclui a figura12 ou as23figuras.


Preparada extensão dos quatroChrome existentes de escopoURA: ler participantes nativos, substituir pelos mesmos IDs em string, conferir persistência exata e recarregar a interface preservando origem autorizada e negação de outra unidade. Não remove cenários, não reativa grants, registra somente IDs sintéticos e preserva a remoção/reinclusão/revogação que o cenário já executava. Ainda não executado.


## Autoridade de autenticação depois da espera real

A extensão Enterprise já revalida AccountUser, alçada de equipe e fontes após o mutex Account, mas ainda usava o User autenticado antes da espera. Preparada a mesma recarga/verificação active_for_authentication? já usada nas escritas operacionais CC, antes de qualquer mutação de participantes.

Três novos casos concorrentes POST/PATCH/DELETE preparados no banco descartável protegido existente. A desconfirmação só ocorre depois de a requisição autenticar e pg_stat_activity comprovar espera real por Account FOR UPDATE; assim não se aceita um401 anterior ao lock como falsa prova. O coordenador anterior mantém seu padrão, e somente esses casos usam alteração diferida. Nenhum usuário real ou sessão externa é alterado. Exige CI nativa do próprioSHA.


### Gate d14f975a — correção dirigida

CI 44435975247: 1205 exemplos Rails distintos aprovados (1046 principais, 74 de concorrência e 85 corporativos), 16 recargas de schema separadas e 534/534 Vue. Um único novo RSpec/MatchArray bloqueou lint Ruby; assets/probe/148 Chrome não executaram. A correção usa contain_exactly com os mesmos dois IDs esperados, sem alterar a asserção funcional ou desativar regras. Nova CI deve comprovar o SHA corrigido. A prévia indireta de retirada por equipe permanece em preparação separada, sem uso nas APIs.
