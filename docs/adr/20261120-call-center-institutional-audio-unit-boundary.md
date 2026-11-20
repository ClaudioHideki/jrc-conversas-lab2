# Biblioteca institucional por unidade — 20/11/2026

Decisão aprovada: separar a biblioteca por unidade operacional nativa e pela cobertura corporativa atual do usuário. Áudio institucional não é gravação de chamada. Team/Unit/Account nativos continuam sendo as autoridades; pastas do Help Center e MediaAssets de Campanhas não serão reutilizados como outro domínio.

Implementar incrementalmente organização e acesso privados. Pastas devem pertencer a uma Account e Unit existentes, com hierarquia somente naquela unidade, revisões, prevenção de ciclos, autorização após o mutex nativo e auditoria de antes/depois. O gerenciamento usa a capacidade configure já existente; não cria grants ou uma nova permissão implícita. Uma pasta não concede acesso à unidade.

Arquivos e versões virão depois desta fundação: ActiveStorage existente, identificação do formato real, hash, duração validada, scanner nativo e bloqueio de entrega enquanto indisponível/não limpo. Não retornar signed_id, chave, service_url ou rails_blob_url. Rotas genéricas de ActiveStorage também precisarão negar blobs protegidos, de forma aditiva, preservando os documentos existentes. Download e prévia devem reautorizar unidade/usuário, verificar integridade e auditar a operação.

Reaproveitar o player existente com opção explícita que preserve o padrão dos demais consumidores. Não expor um botão de download quando a operação não estiver autorizada. Recurso ainda não implementado deve aparecer como pendência, sem contador, duração, vínculo ou sucesso fictício. Não criar TTS ou gravação simulada como evidência de integração real.

Conversão, catálogo de vozes Nico e publicação/versão aplicada no PABX dependem dos contratos reais. Nenhum endpoint, codec obrigatório, ACK ou vínculo publicado será inventado. Edição local nunca troca arquivo em execução. Uma identidade de áudio é independente da pasta e deve manter versões imutáveis; mover/renomear não poderá alterar a versão utilizada. Exclusão dependerá de referências verificáveis, sem supor ausência de uso externo.

Status: decisão e auditoria de reaproveitamento confirmadas; implementação de pastas iniciada separadamente, ainda não homologada. Figuras 5, 6 e 16 permanecem abertas até os respectivos critérios funcionais e visuais.

Preparação da fundação: endpoints internos de pastas (lista/detalhe/criar/editar), popup no card já existente, paginação/pesquisa e movimentação na mesma unidade, revisão/CAS compartilhada e auditoria nativa. A ordem de exclusão de Account/Unit não é alterada; a FK nativa de unidade já restringe exclusão direta da conta, e os testes preservam essa regra. Não existe API de exclusão ou arquivo neste incremento.

A CI deverá provar autorização após espera real pelo lock da Account (perfil, cobertura e autenticação revogados), revisão concorrente e ciclo de hierarquia concorrente. Quatro cenários de Chrome serão acrescentados aos216existentes, em contas sintéticas exclusivas, usando a API e o CSS reais. Recursos de auditoria de pasta e de origem de equipe ganham identificação no filtro e rótulos portugueses; não ganham nova autoridade.

## Fundação validada

fa43cbf7/CI44729757403:1883Rails distintos,101recargas,911Vue,220Chrome e336capturas verificadas. Oito capturas efetivamente revisadas, cobrindo lista/popup em1440/390 e claro/escuro. Aceite somente da organização de pastas por unidade; detalhes em `docs/jrc_contact_center/audio_folder_verified_20261120.json`. Caminho completo, limpeza após negativa e arquivos/versões são incrementos posteriores, ainda sem validação deste SHA.
