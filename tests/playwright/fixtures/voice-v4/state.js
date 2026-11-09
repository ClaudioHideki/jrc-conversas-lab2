import { ref } from 'vue';
export const scenario =
  new URLSearchParams(location.search).get('state') || 'connected';
const idle = scenario === 'idle';
export const accountId = ref(9001);
export const userId = ref(901);
export const record = {
  id: 9009,
  provider: 'synthetic-pabx',
  external_session_id: 'synthetic-session-a',
  correlation_id: 'laboratorio-voz-v4',
  direction: 'inbound',
  status: 'connected',
  contact_id: 9100,
  ani: 'Cliente sintético A',
  dnis: 'Ramal sintético',
  started_at: new Date(Date.now() - 200000).toISOString(),
  answered_at: new Date(Date.now() - 180000).toISOString(),
  lock_version: 2,
  metadata: {
    attendance_observations: {
      text: 'Anotação persistida no cenário sintético.',
    },
  },
  queue: { name: 'Comercial — demonstração' },
  attendant: { name: 'Agente de demonstração' },
  customer: {
    status: 'identified',
    contacts: [
      {
        id: 9100,
        name: 'Cliente sintético A',
        company: { name: 'Empresa de demonstração' },
      },
    ],
  },
};
if (scenario === 'incoming') {
  record.status = 'ringing';
  record.answered_at = null;
}
if (scenario === 'ended') {
  record.status = 'ended';
  record.ended_at = new Date().toISOString();
}
export const sip = Object.fromEntries(
  Object.entries({
    accountId: 9001,
    hasCall: !idle,
    callId: idle ? '' : record.external_session_id,
    incoming: false,
    established: !idle,
    held: false,
    muted: false,
    holdPending: false,
    transferring: false,
    duration: '03:00',
    remoteNumber: 'Cliente sintético A',
    credential: { extension: 'Ramal de laboratório' },
    registered: true,
    configured: true,
    destination: '',
    errorMessage: '',
    sessionState: idle ? '' : 'Established',
    connecting: false,
    extensionEnabled: true,
  }).map(([key, value]) => [key, ref(value)])
);
if (scenario === 'incoming') {
  sip.incoming.value = true;
  sip.established.value = false;
  sip.duration.value = '00:00';
}
if (scenario === 'ended') {
  sip.hasCall.value = false;
  sip.established.value = false;
  sip.sessionState.value = 'Terminated';
}
Object.assign(sip, {
  setMuted: async value => {
    sip.muted.value = value;
  },
  setHold: async value => {
    sip.held.value = value;
  },
  transferCall: async () => true,
  pressKey: () => {},
  hangup: async () => {
    sip.hasCall.value = false;
    sip.established.value = false;
    record.status = 'ended';
    record.ended_at = new Date().toISOString();
  },
  answer: async () => {
    sip.incoming.value = false;
    sip.established.value = true;
    record.status = 'connected';
    record.answered_at = new Date().toISOString();
  },
  reject: async () => {
    sip.hasCall.value = false;
  },
  call: async () => {
    sip.callId.value = 'synthetic-outbound-session';
    sip.remoteNumber.value = sip.destination.value;
    sip.established.value = false;
    sip.hasCall.value = true;
  },
});
export const useSipWebphone = () => sip;
export const useCallsStore = () => ({
  hasActiveCall: false,
  hasIncomingCall: false,
});
export const useWhatsappCallSession = () => ({ isInitiating: ref(false) });
