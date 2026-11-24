# Manual de Cultura JRC — homologação

Base de código: `e674864ccbffbe5d1b5402a2f7acdca9d585089d`, em `ClaudioHideki/jrc-conversas-lab2`. A candidata usa a branch `codex/manual-de-cultura-jrc-20261123`.

## Preparar a homologação

1. Usar uma instância isolada, com banco e Redis próprios, armazenamento Active Storage privado e scanner ClamAV disponível no socket já usado pelo JRC (`JRC_SD_CLAMAV_SOCKET`). Compilar o frontend pelo processo normal do JRC e aplicar as migrations do Manual até `20261124120000_allow_jrc_culture_account_scope.rb` no banco de homologação.
2. Em contas sem unidades do CRM vinculadas a empresas, usar **Conta inteira**. Nas demais, conferir as empresas internas, unidades e coberturas organizacionais ativas para o público inicial.
3. Conceder o papel **Administrador do Manual** somente às pessoas revisadas. Indicar um administrador nativo ativo da mesma conta e o vínculo existente do destinatário. Para concessão por unidade, ambos precisam de cobertura ativa na unidade. O identificador do alvo em `JRC_CULTURE_MEMBER_ID` é de `AccountUser`. O valor em `JRC_CULTURE_ACTOR_ID` é de `User`.

   ```sh
   JRC_CULTURE_ACTION=grant JRC_CULTURE_ACCOUNT_ID='<id da conta>' \
     JRC_CULTURE_ACTOR_ID='<id do usuário administrador nativo>' \
     JRC_CULTURE_MEMBER_ID='<id do vínculo alvo>' JRC_CULTURE_UNIT_ID='<id da unidade ou account>' \
     bundle exec rake jrc_culture:administrator
   ```

   A mesma tarefa com `JRC_CULTURE_ACTION=revoke` desativa o papel e registra a operação. Um papel administrativo nativo sozinho não habilita o portal.

4. Abrir `/portal/manual-de-cultura` com a conta autorizada e usar **Colaboradores** para habilitar os vínculos conferidos. Em **Importação e exportação**, selecionar **Conta inteira** ou a unidade, carregar o XLSX, conferir a prévia e aplicar as linhas válidas. A importação identifica e-mail exato ou usuário único entre os vínculos do escopo selecionado, sinaliza divergências de empresa quando há unidade e mostra associações ambíguas para correção. A aplicação habilita usuários já cadastrados.
5. Em **Publicações e versões**, enviar o PDF original e, se pertinente, o PPTX complementar. Selecionar o público e publicar a versão. Para alterar o PDF ou o termo, criar uma nova versão e publicá-la. Os arquivos definitivos devem ser carregados pela administração autorizada.
6. Com a sessão válida de um colaborador habilitado, clicar em **Manual de Cultura** no menu do JRC e conferir a abertura direta. Em uma janela sem sessão, abrir a mesma rota e conferir o pedido de login. Ler o PDF, clicar em **Li e estou ciente**, conferir a versão e a hora em **Minha ciência** e confirmar a aparição em **Confirmações recentes** na administração. Repetir com uma segunda versão e conferir a nova pendência e o histórico. Verificar o link **UniversidadeJRC** ao lado do novo atalho **Manual de Cultura**.

## Limites operacionais

- A planilha original permanece privada. O pacote Git não contém a planilha nem PDFs/PPTX internos. Cada arquivo é limitado a 15 MiB. A prévia lê até 1.000 linhas de dados.
- Relatórios Excel e PDF respeitam a unidade e os filtros e aceitam até 2.000 registros por exportação. O PDF usa a fonte DejaVu já prevista para os relatórios do JRC.
- O indicador mede os vínculos atribuídos às versões filtradas. Pendente depende de vínculo e cobertura atuais. A confirmação anterior permanece no histórico, inclusive quando o vínculo sai do público atual.
- A confirmação administrativa é interna ao painel do Manual. O painel usa o registro persistido e o escopo atual do administrador, sem avisos externos ou alteração do sino global.
- Ao configurar a primeira unidade vinculada a uma empresa no CRM, conceder os acessos correspondentes por unidade antes de retomar o uso do Manual. Os vínculos de **Conta inteira** deixam de conceder acesso, e os registros já feitos são preservados. A reversão da migration para o esquema antigo exige tratar previamente os registros de **Conta inteira**, pois o esquema antigo exige unidade.

## Validação local de 24/11/2026

- 53 exemplos Rails e 92 testes Vue passaram. O build Vite e a aplicação, reversão e reaplicação da migration em bancos descartáveis passaram.
- Em Chrome, com colaboradores fictícios de uma conta sem unidades do CRM, o atalho abriu o manual usando a sessão do painel. O link direto abriu o login em uma janela sem sessão. Também foram verificados o painel **Conta inteira**, o bloqueio sem habilitação e o destino do link **UniversidadeJRC**.

## Publicação futura

A publicação Docker depende de autorização posterior. Validar a candidata a partir do SHA exato, rodar os gates do JRC, construir com o Dockerfile oficial e verificar boot de Rails/Sidekiq depois da migration no ambiente isolado. Usar tag exclusiva por SHA e registrar o digest. Antes de um futuro deploy autorizado, registrar o digest em execução e o plano de retorno. Preservar as tabelas de ciência ao voltar para uma imagem anterior durante um incidente de aplicação.
