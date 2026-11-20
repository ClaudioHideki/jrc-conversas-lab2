# Expansão nativa das pastas de áudios por unidade

Estado: preparada; testes nativos, Vue e Chrome do incremento ainda pendentes.

A figura 6 exige subpastas expansíveis sem abandonar a lista atual. A navegação existente passa a reutilizar `audio_folders#index`, com a mesma unidade e `parent_id` explícito. Cada ramo carrega somente uma página de vinte filhos quando o usuário o expande. As páginas seguintes mantêm o limite nativo; não há coleta integral nem outro cadastro.

Recolher um ramo descarta seus dados e invalida respostas atrasadas. Alterar conta, unidade, perfil ou cobertura desmonta os ramos; uma resposta antiga não os restaura. A negativa nativa 401/403/404 limpa também a biblioteca e os detalhes. A resposta aceita deve corresponder à conta, à unidade e à pasta pai solicitadas. Isso complementa, sem substituir, a política e o escopo do servidor.

Os nomes continuam ações de navegação e a edição usa o popup existente, com leitura autorizada, revisão e controle de concorrência. As subpastas usam listas e botões de expansão com `aria-expanded` e `aria-controls`; não se anuncia um componente ARIA tree sem implementar seu contrato de teclado. O recuo visual é limitado para preservar a largura de 390 px; a hierarquia permanece completa e o painel tem rolagem própria. Não são inventadas contagens de filhos, usos ou capacidade.

Treze cenários do ramo e um cenário integrado foram preparados com fixtures de transporte, incluindo paginação, respostas atrasadas, mudança de contexto e negativas aninhadas. Os quatro cenários Chrome de pastas existentes passam a exigir expansão, leitura real por pai, recolhimento, navegação de nome com 120 caracteres e largura sem transbordamento, com PostgreSQL e CSS reais em desktop/celular e claro/escuro. As 232 execuções Chrome continuam obrigatórias; a preparação não é homologação.

Nenhuma migration, SQL, permissão, rota ou API foi criada. Áudios publicados, gravação, Nico, usos e exclusão segura permanecem requisitos separados. A biblioteca continua distinta das gravações de chamadas e não publica no PABX.
