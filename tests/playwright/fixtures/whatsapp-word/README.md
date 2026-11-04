# Laboratório visual de conexões

Usa os componentes reais da candidata com respostas sintéticas em memória. Não
simula homologação de telefone nem se conecta a Broker, Evolution ou produção.

Na raiz do repositório:

`pnpm exec vite --config tests/playwright/fixtures/whatsapp-word/vite.config.mjs`

Abra `http://127.0.0.1:5214/tests/playwright/fixtures/whatsapp-word/index.html`.
O parâmetro `?role=agent` exercita a apresentação restrita. Dados, filas e códigos
são exclusivamente demonstrativos, sem números ou credenciais reais.
