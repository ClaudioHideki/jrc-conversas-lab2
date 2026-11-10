# Continuar Atendimento integrado

Ler `2026-11-10-atendimento-voz-estavel.md` e `2026-11-10-atendimento-voz-estavel-resultado.md` nesta pasta. Preservar as branches e todo o diff; não reaplicar patches. LAB2 base d8a83b8; Broker base 29095be.

Código local: lista compartilhada estável com autorização por identidade; paginação por rolagem sem corrida; timeouts de bootstrap; barra persistente/DTMF/discador; preservação da recusa SIP correlacionada; tabulação opcional por empresa. Broker tem apenas suporte ao envelope documentWithCaptionMessage e regressões.

Não houve publicação ou deploy. Não há resposta SIP real da falha externa. Usuário não tem acesso ao PABX. Não pedir que encontre um menu de eventos que ele já confirmou não existir. HTTP 403 de estrutura não é erro SIP. CDR está sem configuração e requer integração própria.

Primeiro gate: RSpec + PostgreSQL/Redis e build integral LAB2, bloqueados pelo Docker HTTP500 e pouco espaço local. Não reiniciar Docker automaticamente; há aplicações de outros trabalhos. Revisar os recursos descartáveis exclusivos listados no relatório antes da limpeza. Não executar backup/dump/restore. Não reenviar UNKNOWN nem ligar números reais.

Depois: CI no SHA candidato, revisão e autorização específica de publicação. Manter produção preservada. Histórico completo do WhatsApp, grupos/mídias históricas e histórico CDR por cliente não foram concluídos.
