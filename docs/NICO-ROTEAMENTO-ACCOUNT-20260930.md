# Roteamento do NICO por Account

O runtime em modo `provider` continua isolado a uma única Account por implantação (`NICO_ALLOWED_ACCOUNTS`). O Rails agora pode selecionar um desses runtimes usando exclusivamente o `account_id` autorizado da sessão/execução. O navegador e o modelo não fornecem endpoint nem credenciais.

## Configuração de instalação

Sem `NICO_RUNTIME_ROUTES`, a configuração existente com `NICO_RUNTIME_URL` e `NICO_SERVICE_TOKEN` permanece válida. Esse modo não transforma o runtime atual em um runtime multiempresa: sua lista de Accounts continua sendo aplicada.

Para várias Accounts, configure `NICO_RUNTIME_ROUTES` no Rails com um objeto JSON. Exemplo ilustrativo, sem segredos:

```json
{
  "101": { "url": "https://nico-empresa-a.internal", "token_env": "NICO_RUNTIME_TOKEN_EMPRESA_A" },
  "202": { "url": "https://nico-empresa-b.internal", "token_env": "NICO_RUNTIME_TOKEN_EMPRESA_B" }
}
```

Configure cada variável referenciada com o segredo de serviço do runtime correspondente (mínimo 32 caracteres). Não versionar os valores. O runtime A autoriza somente 101 e o B somente 202. Em redes externas, usar HTTPS; HTTP permanece disponível para a rede interna do ambiente existente.

Quando o mapa existe, uma Account ausente falha com `account_not_configured`; não há fallback para o runtime global ou para outra empresa. Configuração inválida, URL com credenciais/caminho/query, ou nome de variável fora de `NICO_RUNTIME_TOKEN_*` é rejeitada. A resposta também precisa corresponder ao `account_id` e `request_id` enviados.

Isso vale para análise, operação e transcrição. Credenciais não são serializadas, colocadas no catálogo de ferramentas, enviadas ao navegador ou incluídas no erro apresentado ao usuário. As configurações legadas da tela de provedores JRC AI não são convertidas automaticamente em rotas de runtime.

## Validação e limites

`spec/services/jrc_nico/runtime_client_spec.rb` verifica dois destinos/segredos distintos, Account não mapeada, resposta com Account divergente e configuração inválida. Esses testes usam transporte controlado e não comprovam disponibilidade de um provedor externo.

Nenhuma configuração do LAB, Account, permissão ou implantação de runtime é alterada por esta mudança. O provisionamento dos runtimes, secrets e URLs reais depende da etapa de publicação autorizada. Não remover o guard de uma Account por runtime para contornar a configuração.

## Carga do navegador

O painel consulta o estado a cada cinco segundos somente quando aberto ou com delegação/comando ativo. As notificações passam de quatro para trinta segundos, com atualização ao abrir e ao voltar à aba. Consultas param em aba oculta e não se sobrepõem a uma requisição lenta. Isso reduz consultas ociosas; não substitui medição de latência e carga em homologação.

Erros de envio preservam o rascunho e a identidade da tentativa. O servidor continua responsável pela idempotência, confirmação explícita, autorização atual e registro de resultado. Uma etapa com falha é apresentada separadamente das etapas já concluídas.
