const states = [
  'prepared',
  'dispatching',
  'sent',
  'uncertain',
  'failed',
  'blocked',
  'canceled',
  'completion_reported',
  'declined',
];
const events = [
  'prepared',
  'dispatch_started',
  'send_confirmed',
  'send_uncertain',
  'send_rejected',
  'sender_blocked',
  'canceled_before_send',
  'completion_reported',
  'envelope_canceled',
  'envelope_declined',
];
export const signatureStateKey = state =>
  states.includes(state) ? state : 'unknown';
export const signatureEventKey = kind =>
  events.includes(kind) ? kind : 'unknown';
export const signatureTone = state => {
  if (['failed', 'blocked', 'declined'].includes(state))
    return 'border-n-ruby-6 bg-n-ruby-3 text-n-ruby-12';
  if (['uncertain', 'dispatching', 'completion_reported'].includes(state))
    return 'border-n-amber-6 bg-n-amber-3 text-n-amber-12';
  return 'border-n-blue-6 bg-n-blue-3 text-n-blue-12';
};
