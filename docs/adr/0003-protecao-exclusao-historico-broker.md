# ADR 0003: Proteger o histórico sob custódia antes de qualquer exclusão

- **Status:** Aceita para implementação; release autorizada em 16/11/2026, condicionada aos testes e à verificação de runtime.
- **Data:** 2026-11-16
- **Autores:** equipe JRC e implementação assistida.

## Contexto

Complementa a ADR0002 sem alterar recibos nem remover suas restrições. O usuário confirmou que remover uma conexão deve preservar o histórico. Os testes reais de API, workers, ActiveStorage e PostgreSQL reproduziram exclusão parcial e uma corrida entre criação do recibo e exclusão da conversa (run43961759784: 21 exemplos, 16 falhas esperadas).

## Decisão

Recusar a exclusão destrutiva de registros sob custódia LIVE/V2 antes de enfileirar trabalho e revalidar no executor antes de limpar associações ou objetos privados. Cobrir conta, caixa, conversa, contato, mensagem, anexo, recibo e ActiveStorage. A API retorna conflito `JRC_BROKER_HISTORY_RETAINED` em português. Registros sem custódia mantêm o fluxo normal de exclusão.

Serializar a exclusão com a admissão de recibos mediante lock da conta; proteger também o blob contra a criação concorrente de referências. Não depender de feature flag ou vínculo ativo para proteger o histórico já existente. A exclusão da conta deve recusar antes de alterar usuários ou enfileirar notificações.

A remoção/desconexão e a restauração da mesma caixa são operações distintas do expurgo. Não implementar CASCADE, remoção de recibos, expiração de KEEP ou replay de resultado desconhecido para contornar a proteção. Um futuro expurgo coordenado entre os sistemas exige desenho e autorização próprios.

## Consequências e limites

- Operações de exclusão antes aceitas podem retornar conflito; isso preserva mensagens e arquivos já custodiados.
- O lock da conta serializa operações destrutivas com ingestão. Avaliar duração de exclusões grandes sem enfraquecer a proteção.
- Esta alteração não exige nova migration LAB2 e não altera as migrations já existentes.
- A release inclui a migration LIVE aditiva anterior e precisa aplicá-la antes dos workers compatíveis. Rollback não apaga schema, recibos ou objetos.
- CI, imagem publicada, runtime e entrega física WhatsApp são provas separadas. O estado final deve constar no registro de release, sem converter testes sintéticos em aceite físico.
