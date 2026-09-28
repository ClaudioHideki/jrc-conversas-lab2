(() => {
  const state = {
    registered: false,
    status: 'Aguardando ramal',
    extension: '',
    destination: '',
    remote: '—',
    duration: '00:00',
    incoming: false,
    sessionActive: false,
    established: false,
    muted: false,
    held: false,
    holdPending: false,
    transferring: false,
    errorMessage: '',
  };
  const $ = id => document.getElementById(id);
  const command = payload =>
    window.jrcSoftphoneDesktop.sendFloatingCommand(payload);
  const render = () => {
    $('status').textContent = state.status;
    $('extension').textContent = `Ramal: ${state.extension || '—'}`;
    $('remote').textContent = state.sessionActive ? state.remote || '—' : '—';
    $('duration').textContent = state.duration;
    let callState = 'Ramal não registrado';
    if (state.registered) callState = 'Pronto para ligar';
    if (state.established) callState = 'Em chamada';
    if (state.incoming) callState = 'Chamada recebida';
    $('call-state').textContent = callState;
    $('incoming-actions').classList.toggle('hidden', !state.incoming);
    $('call-actions').classList.toggle(
      'hidden',
      !state.sessionActive || state.incoming
    );
    $('transfer-panel').classList.toggle('hidden', !state.established);
    $('dial-panel').classList.toggle('hidden', state.sessionActive);
    $('dial').disabled =
      !state.registered || !state.destination || state.sessionActive;
    $('mute').textContent = state.muted ? 'Ativar microfone' : 'Mudo';
    $('hold').textContent = state.held ? 'Retomar' : 'Espera';
    $('mute').disabled = !state.established || state.held || state.holdPending;
    $('hold').disabled =
      !state.established || state.holdPending || state.transferring;
    document.querySelectorAll('[data-tone]').forEach(button => {
      button.disabled =
        (state.sessionActive && !state.established) || state.transferring;
    });
    document.querySelectorAll('[data-transfer]').forEach(button => {
      button.disabled =
        !state.established || state.holdPending || state.transferring;
    });
    $('error').textContent = state.errorMessage;
    $('error').classList.toggle('hidden', !state.errorMessage);
  };
  $('destination').addEventListener('input', event => {
    state.destination = event.target.value;
    command({ action: 'setDestination', number: state.destination });
    render();
  });
  $('dial').addEventListener('click', () =>
    command({ action: 'dial', number: state.destination })
  );
  $('answer').addEventListener('click', () => command({ action: 'answer' }));
  $('reject').addEventListener('click', () => command({ action: 'reject' }));
  $('hangup').addEventListener('click', () => command({ action: 'hangup' }));
  $('mute').addEventListener('click', () => command({ action: 'toggleMute' }));
  $('hold').addEventListener('click', () => command({ action: 'toggleHold' }));
  $('open-main').addEventListener('click', () =>
    command({ action: 'showMain' })
  );
  document
    .querySelectorAll('[data-tone]')
    .forEach(button =>
      button.addEventListener('click', () =>
        command({ action: 'dtmf', tone: button.dataset.tone })
      )
    );
  document.querySelectorAll('[data-transfer]').forEach(button =>
    button.addEventListener('click', () =>
      command({
        action: 'transfer',
        mode: button.dataset.transfer,
        destination: $('transfer-destination').value,
      })
    )
  );
  window.jrcSoftphoneDesktop.onFloatingState(next => {
    Object.assign(state, next);
    $('destination').value = state.destination;
    render();
  });
  render();
  window.jrcSoftphoneDesktop.requestFloatingState();
})();
