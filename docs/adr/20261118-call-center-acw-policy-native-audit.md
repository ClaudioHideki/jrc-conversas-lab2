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

## Execução nativa de 5dfa484c

CI 44278344086 aprovou 968 Rails únicos (860/23/85), mais 16 reexecuções da recarga, compatibilidade isolada legada e 321 Vue. Os dez exemplos novos provaram a auditoria, autor/correlação, isolamento, sanitização, no-op e rollback. O gate identificou cinco infrações de indentação somente no spec; Chrome não foi executado. Ajustadas a apresentação do mesmo array esperado e a indentação dos mesmos argumentos, sem remover provas. Exigir novo gate antes do aceite visual. Artefato 14416927294, SHA-256 8ae636ff667c272a948006d88770cd8cf2bcd39c43ed40a8d9212362fade8fb5.


## Aceite incremental comprovado em 0519ee64

CI 44284092413 aprovada: 860 principais + 23 concorrentes + 85 corporativos = 968 exemplos Rails únicos; 16 reexecuções do ledger após recarga separadas; cinco casos legados isolados, 321 Vue e 112 Chrome. Zero falhas, pendências, skips, flaky ou erros externos; migrations/SQL/lints/assets/bootstrap dos 15 cards aprovados. Artefato 14421025672, SHA-256 4b752c36e8642c4b1725941ab378ff7fccae4247eba653b6172e15f14fc645c2.

Conferidos os hashes das 160 capturas; oito revisadas visualmente: auditoria ACW e estado vazio após retirada de cobertura, em desktop/celular e claro/escuro. Popup contido e legível, aviso de registro somente local e valores preservados; listas/seletor sem página 1 de 0. Esses resultados dão aceite ao incremento, não à precedência/revisão global ACW, ao PABX ou às 23 figuras inteiras.
