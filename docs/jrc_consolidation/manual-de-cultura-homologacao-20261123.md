# Manual de Cultura JRC — homologação

Base de código: `e674864ccbffbe5d1b5402a2f7acdca9d585089d`, em `ClaudioHideki/jrc-conversas-lab2`. A candidata usa a branch `codex/manual-de-cultura-jrc-20261123`.

## Preparar a homologação

1. Usar uma instância isolada, com banco e Redis próprios, armazenamento Active Storage privado e scanner ClamAV disponível no socket já usado pelo JRC (`JRC_SD_CLAMAV_SOCKET`). Compilar o frontend pelo processo normal do JRC e aplicar a migration `20261123160000_create_jrc_culture.rb` no banco de homologação.
2. Conferir as empresas internas, unidades e coberturas organizacionais ativas no JRC para o público inicial. O módulo não altera vínculos corporativos, papéis nativos ou o cadastro de usuários.
3. Conceder o papel **Administrador do Manual** somente às pessoas e unidades revisadas. O operador que executa a tarefa abaixo deve indicar um administrador nativo ativo que cubra a unidade. A conta alvo também precisa de vínculo existente e cobertura nessa unidade. O identificador do alvo em `JRC_CULTURE_MEMBER_ID` é de `AccountUser`. O valor em `JRC_CULTURE_ACTOR_ID` é de `User`.

   ```sh
   JRC_CULTURE_ACTION=grant JRC_CULTURE_ACCOUNT_ID='<id da conta>' \
     JRC_CULTURE_ACTOR_ID='<id do usuário administrador nativo>' \
     JRC_CULTURE_MEMBER_ID='<id do vínculo alvo>' JRC_CULTURE_UNIT_ID='<id da unidade>' \
     bundle exec rake jrc_culture:administrator
   ```

   A mesma tarefa com `JRC_CULTURE_ACTION=revoke` desativa o papel e registra a operação. Um papel administrativo nativo sozinho não habilita o portal.

4. Abrir `/portal/manual-de-cultura` com a conta autorizada e usar **Colaboradores** para habilitar os vínculos conferidos. Em **Importação e exportação**, selecionar a unidade, carregar o XLSX, conferir a prévia e aplicar as linhas válidas. A importação identifica e-mail exato ou usuário único entre os vínculos cobertos pela unidade, sinaliza divergências de empresa e mostra associações ambíguas para correção. Trabalhar por unidade. A aplicação nunca cria um novo usuário.
5. Em **Publicações e versões**, enviar o PDF original e, se pertinente, o PPTX complementar. Selecionar as unidades e publicar a versão. Para alterar o PDF ou o termo, criar uma nova versão e publicá-la. Os arquivos definitivos devem ser carregados pela administração autorizada.
6. Abrir o link como colaborador. Ler o PDF, clicar em **Li e estou ciente**, conferir a versão e a hora em **Minha ciência** e confirmar a aparição em **Confirmações recentes** na administração. Repetir com uma segunda versão e conferir a nova pendência e o histórico. Verificar o link **UniversidadeJRC** ao lado do novo atalho **Manual de Cultura**.

## Limites operacionais

- A planilha original permanece privada. O pacote Git não contém a planilha nem PDFs/PPTX internos. Cada arquivo é limitado a 15 MiB. A prévia lê até 1.000 linhas de dados.
- Relatórios Excel e PDF respeitam a unidade e os filtros e aceitam até 2.000 registros por exportação. O PDF usa a fonte DejaVu já prevista para os relatórios do JRC.
- O indicador mede os vínculos atribuídos às versões filtradas. Pendente depende de vínculo e cobertura atuais. A confirmação anterior permanece no histórico, inclusive quando o vínculo sai do público atual.
- A confirmação administrativa é interna ao painel do Manual. O painel usa o registro persistido e o escopo atual do administrador, sem avisos externos ou alteração do sino global.

## Publicação futura

A publicação Docker depende de autorização posterior. Validar a candidata a partir do SHA exato, rodar os gates do JRC, construir com o Dockerfile oficial e verificar boot de Rails/Sidekiq depois da migration no ambiente isolado. Usar tag exclusiva por SHA e registrar o digest. Antes de um futuro deploy autorizado, registrar o digest em execução e o plano de retorno. Preservar as tabelas de ciência ao voltar para uma imagem anterior durante um incidente de aplicação.
