# Conexões WhatsApp — implementação da especificação aprovada

Base: LAB2 `5798160235e95e6b84e01c1d62d172e9d2a26c76`; branch `codex/whatsapp-connections-word-20261104`.
Referência: documento Word V1 fornecido em 04/11, texto completo e sete imagens conferidos.

## Incrementos

1. Reorganizar página em lista horizontal responsiva, tabela de distribuição, ações e ajuda contextual. Preservar escopo por inbox e máquina de pareamento.
2. Completar detalhes com cinco abas: visão geral, distribuição, regras e horários, histórico, configurações. Separar edição de nome da gravação atômica da política. Usar calendário existente, sem horários fictícios.
3. Acrescentar resumo por inbox com métricas reais de 30 dias, autorização de relatórios e ausência de amostra representada por null. Resolução não é tempo de trabalho ativo. Elegibilidade permanece indisponível até existir consulta com paridade comprovada com dispatch.
4. Apresentar QR com instruções, expiração real, confirmação factual e preservação das regras. Nenhuma chamada de pareamento automática ao abrir a página.
5. Corrigir evento de conexão falso no Broker quando apenas um QR é emitido, com regressão, em branch isolada.
6. Executar regressões Vue/API/Rails, build, revisão do diff e verificações visuais desktop/mobile. Distinguir testes sintéticos de homologação de sessão real.

## Limites

Não desconectar, parear, trocar identidade nem enviar mensagens reais para testar layout. Preservar produção, dados, sessões, histórico e alterações de outros trabalhos. Sem backup/dump/restore. Não tratar captura de estado como comprovação de entrega.

## Aceite

Botões levam a jornadas reais; agente não edita política; administrador grava regras auditadas sem redistribuir atendimentos existentes; relógios não são inventados; QR não confirma sessão; nenhum dado antigo de outra conta aparece após troca de contexto. Testes e evidências serão anexados ao checkpoint.
