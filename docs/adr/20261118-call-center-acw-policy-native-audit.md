# Auditoria nativa da política global de pós-atendimento

Estado: implementação preparada; Rails/Vue/Chrome ainda não executados neste incremento.
Complementa as figuras 9 e 14. Não implementa publicação PABX nem toda a precedência de regras do Word.

## Lacuna e solução incremental

AcwPolicy persistia os limites e a obrigatoriedade da voz em Account.settings sem registrar antes/depois na auditoria administrativa. O mesmo serviço passa a capturar somente voz/WhatsApp em segundos e a opção booleana efetiva, dentro do lock/transação Account existentes. A criação do evento nativo é obrigatória: falha reverte a alteração da política. Não há uma nova tabela, endpoint, migration ou histórico paralelo.

O evento usa Audited com associação à conta, tipo Account, comentário exclusivo, ator autenticado e request_uuid nativos. Antes/depois não incluem outras configurações da conta, chaves ou payloads. Valores legados de duração que não sejam inteiros são omitidos com indicação do nome do campo; não são copiados. Salvar o mesmo estado efetivo não gera nova alteração. O valor false explícito da tabulação é preservado.

A consulta nativa de auditoria ganha o tipo acw_policy. A família é excluída da consulta genérica e reintroduzida somente pelo escopo autorizado, como as demais famílias CC. Auditoria de configuração global não é mostrada a cobertura corporativa restrita a empresa/unidade. Consultar detalhe, lista, histórico e exportação continua exigindo conta atual, feature audit_logs e permissão própria de auditoria; filtros enviados pelo cliente não concedem acesso. A escrita mantém configurar e a validação global atuais.

## Interface

A lista completa e a atividade recente reutilizam seus componentes e o mesmo tipo nativo. O detalhe traduz os dois limites em segundos e o booleano, preservando antes/depois. Os quatro casos Chrome de ACW existentes passam a consultar os eventos realmente persistidos, conferir valores anteriores/atuais, abrir histórico e detalhe e capturar o popup nos quatro temas/tamanhos. Não se reduz a cobertura de 112 cenários.

## Verificações preparadas e limites

Dez exemplos Rails: ator/correlação/false; no-op e repetição; histórico/detalhe sem outras configurações; limites inválidos; rollback quando a escrita obrigatória falha; omissão de legado inválido; permissão de auditoria independente; feature nativa; outra conta; cobertura de unidade e endpoint genérico. Quatro Vue novos verificam os rótulos, false, ausência de valor, troca de registro e identificação da política. Os testes isolados antigos mantêm suas asserções, substituindo somente a fronteira Audited na cópia sintética; não são prova de persistência. Um passo explícito do runner executa esses cinco casos separadamente dos Rails.

ESLint direcionado: zero erros e zero novas advertências. Panel conserva nove avisos anteriores e Details conserva três, comparados com o exato 2c6971b8; componente recente e testes novos com zero avisos. Nenhuma regra/configuração é desativada. Execução nativa e visual continuam obrigatórias antes do aceite.

## Pendências preservadas

A revisão otimista global de ACW ainda não foi incorporada aos dois clientes legados; este incremento não afirma resolver conflitos de edição. Não mudam os guardas de revisão dos recursos que já os possuem. Regras por motivo, equipe/fila, precedência, automações por encerramento, decisões de pausas e contrato/ACK do PABX permanecem requisitos separados. Não declarar as 23 figuras concluídas.
