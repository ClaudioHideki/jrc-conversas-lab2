# 2026-11-18 — Autoridade atual nas escritas operacionais

Status: implementado para validação nativa; aceite depende da CI do novo SHA.

## Problema e decisão

Casos e retornos verificavam a permissão antes da criação/alteração, sem compartilhar o mutex Account utilizado pelas revogações. Agora os quatro caminhos de escrita usam AuthorityTransaction, recarregam o usuário e o vínculo e constroem AccessScope/ModulePolicy nativos depois da espera. Não são criadas permissões, modelos ou políticas paralelos. O evento obrigatório e o Case participam da mesma transação; uma falha não pode deixar o caso sem histórico.

O contexto continua derivado da autenticação, a atribuição continua validada pelas filas/usuários da conta e os escopos corporativos permanecem cumulativos. Nenhum acesso adicional por cargo ou parâmetro. Não altera schema, migrations, SQL, provedores ou integrações externas. Enterprise não tem override destes controladores no snapshot revisado.

## Verificação

Nove cenários de APIs, dez corridas reais (caso/retorno versus elegibilidade, perfil, feature, equipe ou cobertura) e duas provas de rollback em banco descartável, sem transação externa de fixture. Guardas de banco/propriedade e barreiras PostgreSQL existentes preservadas. O gate exige relatórios positivos sem falhas/pendências/erros externos. Testes preparados não são resultados aprovados.

## Limites

Não resolve automaticamente vínculos com chamadas/contatos, visibilidade por origem nem a identidade de tentativas de retorno. Permanecem incrementos separados. Contrato PABX indisponível por decisão comunicada pelo usuário; somente fluxos internos, sem ACK ou comando inventado.

## QA visual relacionado

A CI 44302097163 aprovou 984 Rails, 350 Vue e 120 Chrome. Os PNGs reais mostraram overflow interno em 390 px e título pouco legível no tema claro. Ajuste mínimo com Tailwind min-w-0 em fieldset, entrada flexível do CompanyPicker e cor explícita do h1. A nova prova mede controles dentro do fieldset e cartão depois de carregar o Cargo persistido; não esconde campos. As verificações de revisão ACW passam a aguardar o botão habilitado antes da captura.
