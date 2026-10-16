# NICO: caixa Broker anterior ao registro local

Parte P0 da coordenação aprovada. Uma caixa API criada pelo Broker pode existir antes da adoção local no JRC. Sem JrcBrokerInboxBinding ou registro nativo, o NICO atualmente trata essa caixa como envio comum, embora o transporte possa executar um bot.

Reutilizar a adoção administrativa existente, sem criar outra autoridade. Quando o Account possui configuração Broker e o webhook da caixa API aponta para a origem dessa configuração e para a rota canônica `/v1/integrations/chatwoot/:uuid/events`, ausência de vínculo local deve solicitar adoção na configuração Broker antes de preparar ou executar envio público. A URL é somente sinal de rota para impedir bypass, nunca credencial nem autorização para assumir conversa. Não inferir vínculo a partir de custom_attributes fornecidos pelo cliente.

O administrador usa a tela já existente para adotar conexão; Context.adopt! verifica estado remoto e identidade antes de gravar o vínculo. Depois, NICO usa a prévia/confirmar/pausar/enviar existente. Não cadastrar vínculos automaticamente, não consultar HTTP sob locks e não pausar bot durante configuração. Nota privada permanece permitida. Caixa comum e outro Account sem configuração não ganham autoridade Broker.

Revalidar também no momento de executar uma aprovação antiga. Testes sintéticos reproduzem ausência de vínculo com rota conhecida, aprovação anterior à mudança da rota, nota privada e adoção seguida de envio coordenado. Sem alteração em Broker, migrations, ENV ou servidor.

Limite: instalações externas que não anunciam esta rota e não têm registro local precisam do onboarding/adopção explícitos; não é possível descobrir todo executor externo apenas observando uma caixa API.
