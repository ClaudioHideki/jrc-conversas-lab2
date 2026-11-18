# Justificativa local de pausa — 18/11/2026

## Estado

Implementação candidata, aguardando testes nativos e Chrome próprios. Não representa publicação nem homologação PABX.

## Contexto e decisão

Os dois Word exigem configuração granular de justificativa quando aplicável (figuras 7/8). A decisão já aprovada preserva o legado e exige catálogo somente após ativação explícita por conta. Reutilizar a configuração local, o evento e o fluxo de estado existentes, sem um cadastro paralelo.

O administrador pode marcar `justification_required` no motivo, usando as mesmas permissões globais, revisão otimista e auditoria atômica. O campo é opcional no documento persistido: a ausência continua válida e não modifica a assinatura histórica do catálogo. Só um novo envio sob catálogo explicitamente ativado pode exigir texto. Leituras não reescrevem eventos nem configurações antigas.

O texto deve ser string de até 1.000 caracteres e vinculado a um motivo autorizado do catálogo, preservado no metadata do evento nativo. Texto para motivo livre sem definição é rejeitado, evitando uma gravação privada que não teria projeção autorizada na interface; pausas legadas sem esse novo campo continuam aceitas. Valores malformados não são filtrados para uma configuração mais permissiva. O digest de comandos antigos sem texto permanece byte a byte compatível; um comando com texto diferente conflita, e um recibo antigo não é reinterpretado após uma alteração da política.

O conteúdo privado só aparece na resposta autenticada do próprio operador, revalidando conta, autoridade e unidade/perfil nativos. Não integra o DTO genérico do supervisor, nem mesmo para cobertura Group. Usar o filtro de parâmetros já existente; não registrar o texto em logs, auditoria de configuração ou alertas do supervisor. Alterar conta/fila/motivo/autoridade limpa o rascunho da interface; falha mantém o texto para revisão.

## Validação exigida

- Rails/PostgreSQL: formato anterior e assinatura, booleano literal, ativação, rejeição tipada, persistência, repetição e conflito, conta/unidade/perfil e filtro de logs.
- Concorrência: exigência alterada enquanto o operador aguarda o lock da conta deve ser observada antes de qualquer gravação.
- Vue: checkbox sem ativação implícita, ausência preservada no modelo antigo, campo obrigatório/privado e rascunho após erro e mudança de contexto.
- Chrome com banco sintético: ampliar os oito cenários do catálogo, preservando os 136 obrigatórios, quatro projetos e todas as verificações anteriores.

## Limites

Não cria aprovação formal obrigatória, política trabalhista/remuneração, pausa automática nem comando/ACK PABX. O campo não afirma disponibilidade confirmada. As figuras 7/8 e as 23 referências continuam parciais até fechar todos os critérios próprios.
