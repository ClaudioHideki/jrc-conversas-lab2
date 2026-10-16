# NICO e jornada do cliente — versão candidata

## Objetivo e limites autorizados

Executar as recomendações da comparação dos quatro vídeos Astra de 16/10/2026, reutilizando os módulos JRC/NICO/Broker existentes. O JRC continua dono de identidade, permissões e operações de domínio; NICO prepara ações do operador; Broker executa transporte e Flow. Não criar outro executor de bot dentro do JRC.

Todo trabalho JRC/NICO fica em `codex/nico-jornada-candidato-20261016`, com base de produção `98a4be7714be41d33bf9ff52b254ebb773864769` e a correção candidata de paginação. Não substituir imagem nem configuração do servidor atual. O usuário provisionará outro ambiente para homologação.

**Não ativar bot no Broker, publicar/vincular fluxos em caixas, iniciar campanhas, cadências ou respostas automáticas.** Testes usam dados sintéticos e bancos locais descartáveis. Publicação de imagem candidata não é comprovação de implantação.

## Componentes e ordem

1. Base candidata compatível: preservar alterações CRM/PABX do outro desenvolvedor e a paginação corrigida; preparar CI isolado.
2. Análise do NICO: ampliar o relatório já existente, sem nova inferência paralela. Informar versão, caráter inferido, janela efetivamente enviada, truncamento e referências verificadas das evidências. Não tratar inferência como satisfação medida.
3. Coordenação: fechar lacunas de vínculo Broker/JRC, handoff cooperativo e ciclos remotos antes de qualquer envio público do NICO. Prévia, confirmação e pausa continuam obrigatórias.
4. Jornada do cliente: ampliar Customer360 com radar determinístico e visualização de relações autorizadas; não criar banco de grafo separado por antecipação.
5. Público e recorrência: prévia com revisão congelada, recibo por item e inscrição versionada em cadência; resposta, intervenção humana ou cancelamento impedem próximos efeitos.
6. Comandos de domínio e eventos: reutilizar serviços autorizados de CRM, tarefas e agenda; deduplicação, causalidade e resultado incerto explícito. Nenhum SQL ou rota arbitrária escolhida pelo modelo.
7. Agente limitado e conhecimento: ferramentas com escopo, orçamento, limite de passos, referências e revogação por empresa. Subagente não envia ao cliente nem amplia permissões.
8. Voz: distinguir ditado atual, voz contínua do operador e transporte de chamadas WhatsApp. Adaptadores dependem de capacidades reais; interface isolada não certifica áudio ou transferência.

## Primeiro incremento: análise rastreável

Reutilizar `JrcAi::ConversationSentiment`, `JrcNico::RuntimeClient` e o painel NICO. O backend determina a origem da amostra: até 100 mensagens públicas de texto, até 1000 caracteres por mensagem, em ordem cronológica, com IDs, horários e contagem de mensagens cujo texto foi truncado. Notas privadas e anexos não entram na análise.

O resultado preserva os campos anteriores e acrescenta `analysis_version`, `inferred` e `source_window`. Evidências que referenciem IDs fora da amostra fazem o resultado ser rejeitado, mesmo se um runtime antigo aceitar a resposta. Esta verificação confirma a origem da referência, não a veracidade da conclusão do modelo. O relatório bruto do provedor não pode sobrescrever a procedência determinada pelo servidor.

A interface apresenta a advertência de inferência, quantidade, modelo e período legíveis antes dos detalhes JSON. Relatórios antigos continuam renderizando sem os campos novos; não inventar procedência para resultados antigos.

## Homologação e operação

Manter as mesmas famílias de serviços Rails, Sidekiq, PostgreSQL, Redis e runtime NICO; não incluir produção em volumes, redes ou credenciais da homologação. Nenhuma migração destrutiva faz parte do primeiro incremento. Não é necessário alterar o runtime NICO para acrescentar metadados calculados pelo JRC.

Cada entrega registra arquivos, testes e limites. Estados separados: implementado, verificado localmente, CI aprovado, imagem publicada e homologado no servidor. Meta real, Chatwoot externo, chamadas e capacidade de 10 mil conexões exigem ambientes/ativos e evidência própria; não podem ser declarados concluídos por testes de interface.
