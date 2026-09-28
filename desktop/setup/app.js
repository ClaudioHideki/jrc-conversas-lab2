(() => {
  const form = document.getElementById('server-form');
  const input = document.getElementById('server-url');
  const button = document.getElementById('connect');
  const error = document.getElementById('server-error');
  const showError = message => {
    error.textContent = message || '';
    error.classList.toggle('hidden', !message);
  };
  let pending = false;
  window.jrcServerSettings
    .read()
    .then(settings => {
      input.value = settings.origin;
      document
        .getElementById('switch-warning')
        .classList.toggle('hidden', !settings.origin);
      showError(settings.error);
      input.focus();
    })
    .catch(() => showError('Não foi possível ler as configurações.'));
  form.addEventListener('submit', async event => {
    event.preventDefault();
    if (pending) return;
    pending = true;
    button.disabled = true;
    input.disabled = true;
    button.textContent = 'Conectando…';
    showError('');
    try {
      const result = await window.jrcServerSettings.connect(input.value);
      if (!result.ok) showError(result.error);
      else {
        input.value = (await window.jrcServerSettings.read()).origin;
        document.getElementById('switch-warning').classList.remove('hidden');
      }
    } catch {
      showError('Não foi possível configurar o servidor. Tente novamente.');
    } finally {
      pending = false;
      button.disabled = false;
      input.disabled = false;
      button.textContent = 'Conectar';
    }
  });
})();
