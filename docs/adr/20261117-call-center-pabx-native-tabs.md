# Painel técnico PABX: navegação e reuso nativo

Validação do incremento: cf040419, CI 44203813534, 641 Rails/250 Vue/96 Chrome e 120 capturas verificadas. O aceite é interno e sintético; limites externos permanecem.
Estado: decisão registrada antes da implementação. Agrupamento preparado no overlay; validação nativa/Chrome pendente. Base 7011dac7 aprovada; incremento de permissões 4d2868b2 em validação.

## Requisito

As figuras 4 e 13 repetem o painel técnico, sem constituir editor de URA.
Exigem Geral, Ramais, Filas, URAs, Gravações, Sincronização, Diagnóstico e
Auditoria. Não duplicar a tela nem transformar sincronização CDR em publicação
confirmada de inventário. Somente Super Admin altera credenciais/infraestrutura.

## Decisão proposta

Reutilizar PabxSettingsPanel e sua API/validação/criptografia existentes. Uma
opção de apresentação, desativada por padrão, agrupa os mesmos campos e ações
em Geral, Sincronização CDR e Diagnóstico no painel nativo acessado pelo Control
Desk. Outros chamadores mantêm a apresentação completa padrão; a página SIP
poderá optar explicitamente pelo agrupamento, sem mudar os contratos de envio. Campos conservam seu estado ao trocar
as abas; não existe outro armazenamento, conector ou API de credenciais.

As demais entradas navegam para os recursos nativos já autorizados. Operações
sem contrato continuam identificadas como pendentes. A exibição usa a capability
pabx_settings derivada do servidor; a API nativa continua exigindo SuperAdmin e
vínculo na conta. A integração deverá comprovar o descarte do painel ao trocar conta/rota ou
perder autorização, usando os mecanismos nativos existentes. Usuários comuns não montam o formulário privilegiado.

A consulta de configurações não testa conexão nem executa sincronização. Não
preencher cartões com números de mockup. Configurado significa configuração
persistida, não PABX online. Credenciais retornadas seguem mascaradas e não são
copiadas para logs/evidências. Salvar, testar e sincronizar conservam exatamente
os contratos nativos; não introduzir provisionamento ou ACK imaginário.

## Aceite e testes planejados

- Vue: apresentação padrão preservada, agrupamento dos mesmos campos, estado
  conservado, rejeição mantendo rascunho, descarte explícito e guardas ocupadas.
- Chrome real: desktop/celular, dois temas, perfis reais sintéticos e API Rails;
  consultas autenticadas, abas, retorno e ausência de transbordamento.
- Negativo: formulário ausente para administrador comum; endpoint nativo 403.
- Preservar os 92 Chrome e ampliar quando o novo fluxo exigir cenário próprio.
- Não clicar em testes/sincronização de fornecedor nos cenários sem contrato;
  não executar chamadas externas reais ou declarar homologação do PABX.

## Limites

Esta mudança não implementa URA, DAC, política de retenção, publicação de recursos
ou reversão externa. Permanecem dependentes de contrato técnico e homologação.
O catálogo operacional de pausas aguarda a decisão de compatibilidade da API;
nenhum motivo livre legado é bloqueado silenciosamente nesta proposta.

## Evidência visual anterior

Capturas reais de dd8ece07 recuperadas do artefato 14371138060, cujo SHA-256
é eeb7fe79738fb9ea0d86e759b791ec9a8115884dd91e4a85febde45eeec3c07d.
Mobile escuro: 5cea89199e6f90b06a3e50dc05f1ca17525faabdf873ec4168539274fdea937f.
Desktop claro: 16da2883260e77052a72e3167526d5808ee74b8e488777e9f1250d6de0f3d144.
A captura mobile comprova formulário extenso em uma só sequência, sem
transbordamento horizontal; o agrupamento é uma melhoria de uso necessária.
Esta evidência é anterior e não valida uma alteração ainda não implementada.

## Incremento preparado

A página SIP nativa opta explicitamente pelas três abas do painel já existente. Os outros chamadores continuam com a apresentação completa por padrão. Campos, credenciais em branco após salvar, JSON de mapeamento, APIs e controles de tenant são preservados. As abas mantêm rascunhos, possuem navegação por teclado e revelam o campo inválido antes do envio. Descarte é explícito por nova leitura; falha de leitura preserva o rascunho.

Foi identificado um risco concreto: após falha no GET inicial, o formulário antigo permanecia gravável com valores vazios. O incremento mantém os controles desabilitados até uma carga bem-sucedida e oferece nova leitura explícita; não modifica a validação backend nem cria configuração automática. Uma falha posterior ao carregar não apaga a versão revisada.

Oito casos Vue adicionados; quatro casos Chrome Root existentes ampliados com as três abas, estado conservado, URL inválida, descarte e nenhuma requisição de escrita. Os cenários de administrador comum/403 são preservados. Asserções de conexão e sincronização desabilitadas continuam obrigatórias. Nenhuma credencial real é usada; testes Vue com mocks serão diferenciados dos testes HTTP/Chrome reais.

As três abas agrupam operações suportadas hoje, não comprovam as oito áreas completas da referência. Ramais permanecem no cadastro SIP nativo; Filas na Central. URA, políticas de gravação e publicação externa continuam lacunas reais. Não serão criados botões sem implementação nem números ilustrativos.

## Fronteira do formulário nativo

Revisão do RouterView mostrou reutilização do mesmo SipSettingsPage ao mudar somente accountId. A rota passa por um invólucro mínimo, que remonta o formulário por conta/usuário/tipo de perfil, evitando transportar rascunhos ou resultados entre contextos. As APIs e a criptografia não mudam. Dois testes exercitam Vue Router real com formulários sintéticos; não substituem os testes HTTP.

A rota antiga só aceitava o marcador administrator, ausente em perfis personalizados legítimos. A entrada passa a aceitar também a capacidade efetiva jrc_contact_center_administer já existente. Isso permite ao SuperAdmin com perfil CC autorizado chegar ao painel oferecido pela API de administração. Não concede infraestrutura a um administrador comum: SipSettingsPage continua exigindo tipo SuperAdmin e a API nativa continua negando 403. O fixture Chrome agora utiliza a definição real da rota SIP e o consumidor nativo validateLoggedInRoutes, com perfil autenticado obtido do servidor, para provar ambos os caminhos.
