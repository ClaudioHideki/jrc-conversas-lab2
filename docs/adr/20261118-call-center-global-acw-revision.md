# Revisão esperada da política global ACW nos dois clientes nativos

Estado: preparado, sem aceite nativo ou Chrome deste incremento.
Complementa as figuras 9 e 14; não define regras por motivo/fila/equipe nem publica no PABX.

## Problema e menor alteração

O mutex Account já serializa as gravações e revalida o ator, mas duas telas abertas podiam aplicar sequencialmente rascunhos da mesma versão sem perceber a atualização anterior. A política passa a oferecer revisão SHA-256 somente de identidade da conta, limites efetivos ordenados e booleano efetivo. O token não contém outras configurações e não concede acesso. Alterações alheias em Account.settings não invalidam a política.

AcwPolicy verifica a revisão esperada depois de obter/recarregar o lock Account e antes de mudar configurações ou inserir auditoria. A comparação reaproveita ConfigurationRevision e seus erros 409/428. Autorização, elegibilidade atual, cobertura global, transação e auditoria obrigatória permanecem anteriores à escrita. Conflito não grava nem adiciona evento; conta estrangeira não pode fornecer revisão equivalente. Leituras e respostas de escrita são no-store.

O contrato é aditivo: clientes legados que omitem expected_revision mantêm o comportamento nativo, como ocorre nas outras configurações. Isso não é uma garantia de comparação para todo consumidor antigo ou externo. Precondição enviada mas vazia/nula/inválida não é tratada como omissão. Não se impõe quebra global de API nem se declara que consumidores desconhecidos foram atualizados.

## Interface reutilizada

AcwPolicyEditor e o popup administrativo capturam a revisão recebida e usam o composable/componente de conflitos já homologados para unidades, filas, vínculos, perfis e URA. Rascunho é mantido após 409. Recarregar busca a política pelo endpoint real, confere conta/revisão e exibe servidor versus rascunho. Ambos os valores de HH:MM são comparados em segundos sem arredondar silenciosamente. Salvar permanece bloqueado até confirmação explícita; qualquer alteração posterior no rascunho invalida a confirmação. Falha/negação na leitura não libera o botão. A API continua sendo a autoridade.

A tela antiga de Configurações também passa a consultar administration, já existente e autorizado, em vez de inferir autoridade global do indicador configure. configuration_global é derivado pelo servidor da cobertura atual. A estrutura local continua disponível ao configurador restrito e o editor global é substituído pelo aviso nativo. Nenhum endpoint ou permissão nova: os únicos usos anteriores de context eram esses indicadores de configuração. Cinco dos novos Vue cobrem administrador global, cobertura restrita, configurar ausente, conta trocada com resposta atrasada e falha da leitura. O Chrome preparado também força a API como o usuário restrito e exige 401 e política global preservada.

## Validação preparada

Dez casos Rails autenticados: identidade/no-store/privacidade, revisão atual, conflito sem segundo evento, revisão fresca e false, configurações independentes, conta estrangeira, três precondições inválidas e revogação de permissão. Mais uma corrida HTTP real usa o banco descartável e a barreira PostgreSQL já existente: comprova espera em Account FOR UPDATE e rejeição da revisão ultrapassada depois da espera. Os testes antigos de compatibilidade e auditoria permanecem.

Doze Vue novos cobrem os dois clientes e a recarga pelo endpoint ACW, revisão malformada, retenção do rascunho, negação de leitura, conta diferente e invalidação da confirmação. ESLint direcionado tem zero erros e nenhum aviso novo, comparado ao SHA 39121ea2: editor conserva dois, AdministrationSection 32 e painel de comparação dois; demais arquivos zero.

Chrome integrado à fonte para o próximo checkpoint: quatro novos cenários planejados (120 obrigatórios com os 116 preservados), duas sessões em cada cliente, 409 real, revisão/comparação/confirmar/editar/confirmar, persistência por API e doze capturas nos quatro projetos. Só integrar e executar após o incremento de Contato 360º; não atribuir seus resultados a este código.

## Limites

Não há migration, regra comercial, alteração de perfil real, operação PABX ou novo cadastro. A precedência por motivo/fila/equipe, formulários de origem, retomada de ACW e decisões de negócio continuam pendentes. Ambas as figuras continuam parciais. Nenhum build Docker, publicação ou deploy.
