# Rascunhos locais de roteamento no Control Desk

O recurso RoutingRule, seus tipos DDD/cliente/carteira/serviço/alternativa, estados e APIs de escrita já existem. O incremento reutiliza esse armazenamento e o card Distribuição; não cria cadastro de números, equipes, filas ou outro motor externo.

## Escrita e histórico

Criar/editar aguarda o mutex Account nativo e depois revalida usuário ativo, vínculo, elegibilidade, configure e escopo atual antes de localizar regra/destinos. A revisão canônica existente é retornada no catálogo/detalhe; a interface exige a revisão para editar. Clientes anteriores sem o parâmetro mantêm o contrato; parâmetro presente inválido é rejeitado. Registros published continuam sem atualização pela API. Pedir publicação ainda exige a capacidade própria e termina indisponível, sem comando PABX.

A auditoria obrigatória de antes/depois usa a trilha nativa e a mesma transação; falha de inserção reverte o rascunho. Escopos anterior e posterior incluem a unidade real da fila e a cobertura corporativa histórica. Condições legadas opacas não entram no histórico nem em logs novos; apenas o nome do campo omitido. O filtro e o histórico existentes reconhecem routing_rule. A lista/detalhe revalidam conta e cobertura; paginação nativa e filtros por tipo/estado/busca reutilizam o contrato atual.

## Interface incremental

O card Distribuição mantém seu nome, ícone e pendência externa. A área nova oferece rascunhos, filtros/paginação na URL, popup contido, criação/edição, recarga real, comparação da revisão concorrente e confirmação de revisão. Reutiliza Dialog, ConfigurationRevisionConflict e os seletores paginados de unidades/filas. O seletor continua voiceOnly por padrão para todas as URAs; somente o contexto de roteamento pode listar os canais já aceitos pelo backend nativo. Não há publicação ou teste externo habilitado.

A edição comum preserva as condições e janelas existentes, que não são regravadas pelo formulário. Regra antiga com destino apenas por fila preserva target_unit_id nulo: a unidade autorizada é consultada somente para contexto visual do seletor. Troca de conta/perfil limpa os dados; respostas tardias não são montadas. Escrita em andamento impede clique duplicado; erro conserva o rascunho para revisão segura.

## Limites e validação pendente

Não representa o cadastro institucional de números, calendário/DAC completo, simulação do roteador ou editor de condições/janelas avançadas. Essas lacunas permanecem na matriz dos Word. Não há novos parâmetros reais, grant, migration ou fornecedor. A publicação/ACK real depende do contrato PABX indisponível.

Preparados testes Rails HTTP de escopo, revisão, histórico, publicação negada, preservação legada e paginação; sete testes HTTP não transacionais adicionais cobrem seis corridas de revogação e rollback real da auditoria. Testes Vue incluem revisão, lookup legado, mudança de conta/perfil e erro/duplicação. Quatro Chrome com banco sintético cobrem criação, recarga, edição, conflito, paginação, negações e temas. Exigir o próximo SHA/CI com148/148 Chrome; preparação e lint não equivalem a homologação.

## Primeira execução nativa

CI44418507109/adf4101b coletou1.039 exemplos principais:1.038 aprovados e uma falha de preparação do histórico por unidade;16 recargas aprovadas. O fixture configurou unidades sem cobertura corporativa inicial do administrador. A negativa real daAPI é correta: manter as permissões e declararGROUP no próprio usuário sintético antes de criar os dois registros, depois substituir essa mesma fonte pelaUnidadeA. Conferir201 de cada criação e conservar todas as negativasB. Um novo cenário comprova que administrador elegível sem cobertura explícita não grava na estrutura configurada. Corrigidos22 apontamentos Ruby somente nos dois specs, sem suprimir cops. Concorrência/Vue/assets/Chrome ainda não foram executados nesseSHA; exigir próximo gate148/148. Artefato14482776042 / 42c22a2edbc5964ec399c9a9e91dddcc75d28d6019b79a4a7fcde5db857c269e verificado.


## QA db20cf5c — contrato do Dialog

CI44423463990:1.196 Rails distintos (1.040 principais,71 concorrentes,85 corporativos),16 recargas e zero novas infrações Ruby aprovados; Vue436/440,quatro falhas por `dialog.value?.close is not a function`. Assets eChrome não executados. Artefato14483643068,182.183bytes,SHA-256 93047f2b4d881c6bd2d6c2a89c0eb1455ee981f505845168864d6cc78ce2d29d, recuperado e verificado.

O Dialog real do próprio SHA expõe open/close (defineExpose na linha132); o stub booleano do spec não os implementava. Corrigido o substituto para expor esse mesmo contrato e acrescentada a verificação de fechamento ao revogar configure. Preservadas as seis verificações funcionais, filtros, paginação e negações; nenhum fallback foi adicionado ao produto para ocultar o erro de fixture.

Próximo checkpoint também contém o incremento ACW de autoridade atual, preparado separadamente e descrito em seu ADR. Ambos exigem os gates do próprioSHA; não há aceite Chrome herdado.
