import {
  Invitation,
  Inviter,
  RegistererState,
  SessionState,
  UserAgent,
} from 'sip.js';
import { SipRegisterer } from './SipRegisterer';
import { sanitizeSipMessage } from './sipErrors';

const CONNECTION_TIMEOUT_SECONDS = 10;
const DTMF_SEQUENCE_GAP_MS = 300;
const TRANSFER_ACTIVATION_DELAY_MS = 900;
const TRANSFER_CONFIRM_DELAY_MS = 500;
const TRANSFER_DTMF_CODES = Object.freeze({
  immediate: { prefix: '*3', suffix: '#' },
  supervised: { prefix: '*4', suffix: '#' },
});
const REGISTRATION_ERRORS = Object.freeze({
  401: 'Usuário ou senha SIP não autorizados (401)',
  403: 'Registro recusado pelo servidor; confira usuário e senha (403)',
  404: 'Ramal ou domínio SIP não encontrado (404)',
  408: 'O servidor não respondeu ao registro SIP (408)',
  503: 'O serviço SIP está temporariamente indisponível (503)',
});

export class SipClient {
  constructor(callbacks = {}) {
    this.callbacks = callbacks;
    this.userAgent = null;
    this.registerer = null;
    this.session = null;
    this.remoteStream = null;
    this.direction = null;
    this.muted = false;
    this.held = false;
    this.wasEstablished = false;
    this.terminationExpected = false;
    this.callLockRelease = null;
    this.callStarting = false;
    this.transportConnected = false;
    this.transferInProgress = false;
    this.holdPending = false;
    this.cancelHold = null;
    this.cancelRegistration = null;
  }

  get registered() {
    return (
      this.transportConnected &&
      this.registerer?.state === RegistererState.Registered
    );
  }

  get hasCall() {
    return Boolean(
      this.session && this.session.state !== SessionState.Terminated
    );
  }

  emit(name, ...args) {
    this.callbacks[name]?.(...args);
  }

  log(category, message) {
    const safeMessage = sanitizeSipMessage(message, [
      this.configuration?.password,
      this.configuration?.username,
    ]);
    // Raw exceptions/SIP messages can carry Authorization and session material.
    this.emit('onLog', { category, message: safeMessage, details: '' });
    // eslint-disable-next-line no-console
    const logger = category === 'ERRO SIP' ? console.error : console.info;
    logger(`[SIP] ${safeMessage}`);
  }

  setStatus(label, tone = 'neutral') {
    this.emit('onStatus', { label, tone });
  }

  async connect(configuration) {
    if (this.registered) return;
    if (this.userAgent) await this.disconnect();
    this.configuration = { ...configuration };
    const uri = UserAgent.makeURI(
      `sip:${configuration.extension}@${configuration.sip_domain}`
    );
    if (!uri) throw new Error('Não foi possível criar a identidade SIP');
    this.setStatus('Conectando ao ramal', 'warning');
    const userAgent = new UserAgent({
      uri,
      authorizationUsername: configuration.username,
      authorizationPassword: configuration.password,
      userAgentString: 'Hodu',
      transportOptions: {
        server: configuration.wss_server,
        connectionTimeout: CONNECTION_TIMEOUT_SECONDS,
      },
      delegate: {
        onConnect: () => {
          if (this.userAgent !== userAgent) return;
          this.transportConnected = true;
          this.emit('onTransport', 'Conectado');
          this.log('TRANSPORTE', 'WebSocket conectado');
        },
        onDisconnect: () => {
          if (this.userAgent !== userAgent) return;
          this.transportConnected = false;
          this.emit('onTransport', 'Desconectado');
          this.setStatus('Conexão perdida', 'error');
          this.log('TRANSPORTE', 'WebSocket desconectado');
        },
        onInvite: invitation => {
          this.receive(invitation).catch(() => {
            this.log('ERRO SIP', 'Erro SIP ao receber chamada');
            this.emit('onError', 'Erro SIP ao receber chamada');
          });
        },
      },
      logBuiltinEnabled: false,
      logConfiguration: false,
    });
    this.userAgent = userAgent;
    let cancelRegistration;
    try {
      await userAgent.start();
      if (this.userAgent !== userAgent) return;
      let resolveRegistration;
      let rejectRegistration;
      const registered = new Promise((resolve, reject) => {
        resolveRegistration = resolve;
        rejectRegistration = reject;
      });
      cancelRegistration = () =>
        rejectRegistration(new Error('Registro SIP cancelado'));
      this.cancelRegistration = cancelRegistration;
      const registerer = new SipRegisterer(userAgent, {
        onAccept: () => {
          if (this.userAgent !== userAgent) return;
          this.emit('onRegister', 'Registered');
          this.log('REGISTRO', 'REGISTER aceito');
          resolveRegistration();
        },
        onReject: response => {
          if (this.userAgent !== userAgent) return;
          const statusCode = Number(response?.message?.statusCode) || 0;
          const message =
            REGISTRATION_ERRORS[statusCode] ||
            `Registro SIP rejeitado (${statusCode || 'sem código'})`;
          const retryAfter = Number.parseInt(
            response?.message?.getHeader?.('retry-after'),
            10
          );
          const retryAfterMs =
            Number.isFinite(retryAfter) && retryAfter > 0
              ? retryAfter * 1000
              : 0;
          this.emit('onRegistrationFailure', {
            permanent:
              statusCode >= 400 &&
              statusCode < 500 &&
              ![408, 423, 480].includes(statusCode),
            retryAfterMs,
          });
          this.emit('onRegister', `Rejeitado (${statusCode || 'sem código'})`);
          this.emit('onError', message);
          this.setStatus('Falha no registro', 'error');
          this.log('REGISTRO', message);
          rejectRegistration(new Error(message));
        },
        onRedirect: () => {
          if (this.userAgent !== userAgent) return;
          this.emit('onRegistrationFailure', {
            permanent: true,
            retryAfterMs: 0,
          });
          rejectRegistration(new Error('Redirecionamento SIP não autorizado'));
        },
      });
      this.registerer = registerer;
      registerer.stateChange.addListener(state => {
        if (this.registerer !== registerer) return;
        const retryAfterMs =
          Math.max(0, Number(registerer.retryAfter) || 0) * 1000;
        this.emit('onRegister', String(state), { retryAfterMs });
        if (state === RegistererState.Registered) {
          this.setStatus('Ramal registrado', 'success');
          this.log('REGISTRO', 'Ramal registrado');
        }
        if (state === RegistererState.Unregistered) {
          this.setStatus('Registro perdido', 'warning');
        }
        if (state === RegistererState.Terminated) {
          this.setStatus('Registro encerrado', 'error');
        }
      });
      this.setStatus('Registrando ramal', 'warning');
      this.emit('onRegister', 'Registrando');
      // register() alone resolves when the request is sent, not when REGISTER succeeds.
      await Promise.all([registerer.register(), registered]);
    } catch (error) {
      if (this.userAgent === userAgent) {
        this.userAgent = null;
        this.registerer = null;
        await userAgent.stop().catch(() => {});
        this.transportConnected = false;
        this.emit('onTransport', 'Desconectado');
        this.setStatus('Falha ao conectar', 'error');
        this.log('ERRO SIP', 'Erro SIP ao conectar ou registrar');
      }
      throw error;
    } finally {
      if (this.cancelRegistration === cancelRegistration)
        this.cancelRegistration = null;
    }
  }

  configureSession(session, direction) {
    this.session = session;
    this.direction = direction;
    this.muted = false;
    this.held = false;
    this.wasEstablished = false;
    this.terminationExpected = false;
    this.remoteStream = new MediaStream();

    session.delegate = {
      onBye: bye => {
        this.log('CHAMADA', 'Chamada encerrada pelo destino (BYE)');
        bye.accept();
      },
      onCancel: () => this.log('CHAMADA', 'Chamada cancelada pelo destino'),
      onSessionDescriptionHandler: handler => {
        this.attachPeerConnection(handler.peerConnection);
      },
    };

    this.emitSessionState(session, session.state);

    session.stateChange.addListener(state => {
      if (this.session !== session) return;
      this.log('CHAMADA', `Estado SIP: ${String(state)}`);
      this.emitSessionState(session, state);
      if (state === SessionState.Established) {
        this.wasEstablished = true;
        this.setStatus('Em chamada', 'success');
        this.attachPeerConnection(
          session.sessionDescriptionHandler?.peerConnection
        );
        this.emit('onEstablished');
      }
      if (state === SessionState.Terminated) {
        if (!this.wasEstablished && !this.terminationExpected) {
          const message =
            'A sessão SIP foi encerrada antes de a chamada ser atendida.';
          this.emit('onError', message);
          this.setStatus('Chamada encerrada pelo PABX', 'error');
          this.log('CHAMADA', message);
        }
        this.finishCall(!this.wasEstablished);
      }
    });
  }

  emitSessionState(session, state) {
    this.emit('onSession', {
      state: String(state),
      direction: this.direction,
      remote: this.remoteIdentity(session),
      callId: session.request?.callId || session.id,
    });
  }

  attachPeerConnection(peerConnection) {
    if (!peerConnection) return;
    peerConnection.addEventListener('track', event => {
      event.streams?.[0]?.getTracks().forEach(track => {
        if (!this.remoteStream.getTracks().some(item => item.id === track.id)) {
          this.remoteStream.addTrack(track);
        }
      });
      this.emit('onRemoteStream', this.remoteStream);
    });
  }

  remoteIdentity(session = this.session) {
    return session?.remoteIdentity?.uri?.user || '—';
  }

  async receive(invitation) {
    if (this.hasCall || this.callStarting) {
      await invitation.reject({ statusCode: 486, reasonPhrase: 'Busy Here' });
      return;
    }
    if (!(await this.acquireCallLock())) {
      this.log('CHAMADA', 'Chamada ignorada; outra aba está responsável');
      await invitation.reject({ statusCode: 486, reasonPhrase: 'Busy Here' });
      return;
    }
    this.configureSession(invitation, 'entrada');
    invitation.progress({ statusCode: 180 });
    this.setStatus('Chamada recebida', 'warning');
    const remote = this.remoteIdentity(invitation);
    this.log('CHAMADA', 'Chamada recebida');
    this.emit('onIncoming', {
      remote,
      callId: invitation.request?.callId || invitation.id,
    });
  }

  async call(destination) {
    if (!this.registered) throw new Error('O ramal ainda não está registrado');
    if (this.hasCall || this.callStarting) {
      throw new Error('Já existe uma chamada ativa');
    }
    this.callStarting = true;
    let inviter;
    try {
      const cleanDestination = String(destination).replace(/[\s()-]/g, '');
      const target = UserAgent.makeURI(
        cleanDestination.startsWith('sip:')
          ? cleanDestination
          : `sip:${cleanDestination}@${this.configuration.sip_domain}`
      );
      if (!target) throw new Error('Número ou ramal de destino inválido');
      if (!(await this.acquireCallLock())) {
        throw new Error('Já existe uma chamada SIP ativa em outra aba');
      }

      inviter = new Inviter(this.userAgent, target, {
        sessionDescriptionHandlerOptions: {
          constraints: { audio: true, video: false },
          iceGatheringTimeout: 8000,
        },
      });
      this.configureSession(inviter, 'saída');
      this.callStarting = false;
      this.setStatus('Discando', 'warning');
      await inviter.invite({
        requestDelegate: {
          onTrying: () => {
            this.log('CHAMADA', 'PABX recebeu a solicitação de chamada');
          },
          onProgress: response => {
            const statusCode = response?.message?.statusCode;
            this.setStatus('Chamando', 'warning');
            this.log(
              'CHAMADA',
              `Destino em progresso${statusCode ? ` (${statusCode})` : ''}`
            );
          },
          onAccept: response => {
            const statusCode = response?.message?.statusCode || 200;
            this.log('CHAMADA', `Chamada atendida (${statusCode})`);
          },
          onReject: response => {
            const statusCode = response?.message?.statusCode;
            const details = Number(statusCode) || 'sem código';
            const message = `O PABX recusou a chamada (${details}).`;
            this.emit('onError', message);
            this.setStatus('Chamada recusada', 'error');
            this.log('CHAMADA', message);
          },
        },
      });
    } catch (error) {
      this.callStarting = false;
      this.terminationExpected = true;
      if (this.session === inviter) this.finishCall(true);
      else this.releaseCallLock();
      throw error;
    }
  }

  async answer() {
    if (!(this.session instanceof Invitation)) {
      throw new Error('Não existe chamada recebida para atender');
    }
    try {
      await this.session.accept({
        sessionDescriptionHandlerOptions: {
          constraints: { audio: true, video: false },
          iceGatheringTimeout: 8000,
        },
      });
      this.log('CHAMADA', 'Chamada atendida');
    } catch (error) {
      this.log('ERRO SIP', 'Erro SIP ao atender chamada', error);
      throw error;
    }
  }

  async reject() {
    if (!(this.session instanceof Invitation)) {
      throw new Error('Não existe chamada recebida para recusar');
    }
    this.terminationExpected = true;
    await this.session.reject({ statusCode: 486, reasonPhrase: 'Busy Here' });
    this.setStatus('Chamada recusada', 'neutral');
    this.log('CHAMADA', 'Chamada recusada');
  }

  async hangup() {
    const session = this.session;
    if (!session || session.state === SessionState.Terminated) return;
    if (session.state === SessionState.Terminating) return;

    this.terminationExpected = true;
    this.setStatus('Encerrando chamada', 'warning');
    if (session.state === SessionState.Established) {
      await session.bye();
    } else if (session instanceof Invitation) {
      await session.reject({ statusCode: 480 });
    } else if (session instanceof Inviter) {
      await session.cancel();
    }
  }

  setMuted(muted) {
    const tracks = this.session?.sessionDescriptionHandler?.peerConnection
      ?.getSenders()
      .map(sender => sender.track)
      .filter(track => track?.kind === 'audio');
    if (!tracks?.length)
      throw new Error('Nenhum microfone ativo foi encontrado');
    tracks.forEach(track => {
      track.enabled = !muted && !this.held;
    });
    this.muted = muted;
    this.emit('onMute', muted);
  }

  async setHold(held) {
    const session = this.session;
    if (session?.state !== SessionState.Established) {
      throw new Error('Não existe chamada estabelecida');
    }
    if (this.holdPending || this.transferInProgress) {
      throw new Error('Aguarde a operação de chamada em andamento');
    }
    this.holdPending = true;
    this.emit('onHoldPending', true);
    try {
      await new Promise((resolve, reject) => {
        this.cancelHold = () => reject(new Error('A chamada foi encerrada'));
        session
          .invite({
            sessionDescriptionHandlerOptions: { hold: held },
            requestDelegate: {
              onAccept: resolve,
              onReject: () =>
                reject(new Error('O PABX recusou a alteração de espera')),
            },
          })
          .catch(reject);
      });
      if (
        this.session !== session ||
        session.state !== SessionState.Established
      ) {
        throw new Error('A chamada foi encerrada');
      }
      this.held = held;
      const peerConnection = session.sessionDescriptionHandler?.peerConnection;
      peerConnection?.getSenders().forEach(sender => {
        if (sender.track?.kind === 'audio')
          sender.track.enabled = !held && !this.muted;
      });
      peerConnection?.getReceivers().forEach(receiver => {
        if (receiver.track?.kind === 'audio') receiver.track.enabled = !held;
      });
      this.emit('onHold', held);
      this.setStatus(
        held ? 'Chamada em espera' : 'Em chamada',
        held ? 'warning' : 'success'
      );
    } finally {
      this.cancelHold = null;
      this.holdPending = false;
      this.emit('onHoldPending', false);
    }
  }

  async sendDtmf(tone) {
    const handler = this.session?.sessionDescriptionHandler;
    if (!handler || this.session?.state !== SessionState.Established) {
      throw new Error('Não existe chamada estabelecida para enviar DTMF');
    }
    if (handler.sendDtmf?.(tone, { duration: 160, interToneGap: 70 })) return;
    await this.session.info({
      requestOptions: {
        body: {
          contentDisposition: 'render',
          contentType: 'application/dtmf-relay',
          content: `Signal=${tone}\r\nDuration=160`,
        },
      },
    });
  }

  async sendDtmfSequence(sequence, session = this.session) {
    const tones = String(sequence || '').split('');
    if (!tones.length) throw new Error('Informe os tons DTMF para enviar');
    if (this.session?.state !== SessionState.Established) {
      throw new Error('Nao existe chamada estabelecida');
    }

    // Sequential DTMF delivery is required by the PABX transfer protocol.
    // eslint-disable-next-line no-restricted-syntax
    for (const tone of tones) {
      if (this.session !== session) throw new Error('A chamada foi encerrada');
      // eslint-disable-next-line no-await-in-loop
      await this.sendDtmf(tone);
      // eslint-disable-next-line no-await-in-loop
      await new Promise(resolve => {
        window.setTimeout(resolve, DTMF_SEQUENCE_GAP_MS);
      });
    }
  }

  async transfer(type, destination) {
    if (this.transferInProgress || this.holdPending) {
      throw new Error('Aguarde a operação de chamada em andamento');
    }
    const cleanDestination = String(destination || '').replace(/[^\d+]/g, '');
    if (!cleanDestination)
      throw new Error('Informe o ramal ou numero de destino');
    const session = this.session;
    const transferCode =
      TRANSFER_DTMF_CODES[type] || TRANSFER_DTMF_CODES.immediate;
    this.transferInProgress = true;
    this.emit('onTransferPending', true);
    try {
      await this.sendDtmfSequence(transferCode.prefix, session);
      await new Promise(resolve => {
        window.setTimeout(resolve, TRANSFER_ACTIVATION_DELAY_MS);
      });
      await this.sendDtmfSequence(cleanDestination, session);
      await new Promise(resolve => {
        window.setTimeout(resolve, TRANSFER_CONFIRM_DELAY_MS);
      });
      await this.sendDtmfSequence(transferCode.suffix, session);
      this.log(
        'TRANSFERENCIA',
        `${type === 'supervised' ? 'Supervisionada' : 'Imediata'} enviada`
      );
    } finally {
      this.transferInProgress = false;
      this.emit('onTransferPending', false);
    }
  }

  finishCall(preserveStatus = false) {
    this.cancelHold?.();
    this.stopSessionMedia();
    if (!preserveStatus) this.setStatus('Chamada encerrada', 'neutral');
    this.log('CHAMADA', 'Chamada encerrada');
    this.emit('onEnded');
    this.emit('onRemoteStream', null);
    this.session = null;
    this.remoteStream = null;
    this.direction = null;
    this.muted = false;
    this.held = false;
    this.wasEstablished = false;
    this.terminationExpected = false;
    this.callStarting = false;
    this.releaseCallLock();
  }

  async disconnect() {
    const userAgent = this.userAgent;
    const registerer = this.registerer;
    this.cancelRegistration?.();
    this.userAgent = null;
    this.registerer = null;
    try {
      await this.hangup();
      if (registerer?.state === RegistererState.Registered) {
        await registerer.unregister();
      }
    } finally {
      try {
        await userAgent?.stop();
      } finally {
        this.transportConnected = false;
        this.configuration = null;
        this.finishCall();
        this.emit('onTransport', 'Desconectado');
        this.emit('onRegister', 'Não registrado');
        this.setStatus('Desconectado', 'neutral');
      }
    }
  }

  stopSessionMedia() {
    const peerConnection =
      this.session?.sessionDescriptionHandler?.peerConnection;
    peerConnection?.getSenders().forEach(sender => sender.track?.stop());
    peerConnection?.getReceivers().forEach(receiver => receiver.track?.stop());
    this.remoteStream?.getTracks().forEach(track => track.stop());
  }

  async acquireCallLock() {
    if (!navigator.locks?.request || this.callLockRelease) return true;

    const lockName = `jrc-sip-${this.configuration.sip_domain}-${this.configuration.extension}`;
    let resolveAcquisition;
    const acquisition = new Promise(resolve => {
      resolveAcquisition = resolve;
    });

    navigator.locks
      .request(lockName, { ifAvailable: true }, async lock => {
        if (!lock) {
          resolveAcquisition(false);
          return;
        }
        resolveAcquisition(true);
        await new Promise(resolve => {
          this.callLockRelease = resolve;
        });
      })
      .catch(error => {
        this.log('ERRO SIP', 'Falha ao coordenar chamada entre abas', error);
        resolveAcquisition(true);
      });

    return acquisition;
  }

  releaseCallLock() {
    this.callLockRelease?.();
    this.callLockRelease = null;
  }
}
