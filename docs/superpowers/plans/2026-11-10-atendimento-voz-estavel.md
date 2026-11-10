# Atendimento integrado, voz e sincronização

Base LAB2: d8a83b824b11cc68ddbbce7c79681f368051fb70. Branch: codex/atendimento-voz-estavel-20261110.

## Especificação aprovada

Preservar a lista conjunta existente de Voz, caixas WhatsApp e e-mail. Não criar abas para separar esses canais. Dentro de Voz, simplificar discagem, manter a chamada durante navegação, oferecer histórico por cliente e tabulação configurável por empresa. Corrigir os desaparecimentos periódicos da lista e carregar páginas adicionais por rolagem sem perder seleção. Broker continua independente, multi-tenant, com Evolution pinada. Não confundir importação histórica disponível com espelhamento completo do celular.

Sem deploy, envio real, desconexão, alteração de credenciais, migração produtiva ou backup neste incremento. Gabriela não está disponível para login; testes de seu perfil serão testes de autorização, não uma homologação com sua sessão real.

## Task 1: Lista estável e permissões

- [ ] Adicionar regressão em InboxList.spec.js: manter registros já autorizados durante revalidação; ocultar registros novos ou cuja atribuição mudou até resposta; revogação, erro e troca de Account continuam fechando acesso.
- [ ] Corrigir InboxList.vue com admissão por identidade de conversa/caixa/responsável/time. Não usar cache irrestrito de permissões.
- [ ] Executar a suíte InboxList e revisar Enterprise. Commit seletivo.

## Task 2: Rolagem das conversas

- [ ] Adicionar regressões ao workspace para carregamento pelo fim da lista, requisição única, botão de recuperação e filtros.
- [ ] Adicionar sentinela no contêiner rolável existente, sem substituir InboxChannelGroups, preservando paginação do backend e seleção.
- [ ] Executar testes de workspace/lista e lint dos arquivos. Commit seletivo.

## Task 3: Voz compacta integrada

- [ ] Testar barra persistente, controles compactos, teclado recolhido e discador acessível no layout existente.
- [ ] Usar GlobalVoiceBar, InboxVoicePanel e OutboundVoiceDialog e o singleton SIP atual; manter permissões e identidade de sessão.
- [ ] Testar navegação, discagem, controles e jornada de pós-atendimento existentes. Não acoplar novos canais a abas.

## Task 4: Backend de voz e Broker

- [ ] Conferir política de tabulação por empresa, histórico/CDR e limites das APIs existentes. Implementar somente com contrato e regressão verificáveis; registrar os bloqueios de identidade dos múltiplos registros CDR.
- [ ] Inspecionar contratos de histórico da Evolution/Broker e receptor silencioso LAB2 antes de ampliar grupos/mídias; preservar KEEP, deduplicação e mensagens em tempo real.
- [ ] Implementar incrementos comprováveis, sem afirmar captura de histórico que a engine não entregou.

## Task 5: Verificação e entrega

- [ ] Rodar lint, testes afetados e build; distinguir ambiente local, CI e produção. Registrar falhas e dependências.
- [ ] Revisão independente do diff completo, correções importantes e regressões.
- [ ] Atualizar checkpoint e matriz com código, evidências e lacunas reais. Não gerar release sem gates concluídos.

Interfaces compartilhadas: Task 1 controla admissão antes de Task 2 paginar. Task 3 preserva singleton SIP e contratos usados pelo backend da Task 4. Histórico deve usar persistência e receptor silencioso existentes; nenhuma ação histórica deve executar bots, alterar atribuição ou contar como nova mensagem não lida.
