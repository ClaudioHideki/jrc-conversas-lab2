import { record } from './state';
const data = body => Promise.resolve({ data: { account_id: '9001', ...body } });
export const context = {
  capabilities: { operate: true },
  provider: {
    key: record.provider,
    capabilities: {
      sip_webrtc: 'available',
      hold: 'available',
      transfer_blind: 'available',
      transfer_attended: 'available',
    },
  },
};
const agent = {
  account_user_id: '901',
  state: 'available',
  state_version: '1',
  pending_qualifications: [],
  queues: [],
  provider_confirmed: false,
};
const qualification = () => ({
  id: 9901,
  account_id: 9001,
  account_user_id: '901',
  channel: 'voice',
  call_session_id: record.id,
  started_at: new Date().toISOString(),
  completed_at: null,
  acw_limit_seconds: 180,
});
export default {
  context: () => data(context),
  agentState: () => data({ item: agent }),
  calls: (_, params) =>
    data({
      items:
        params.external_session_id === record.external_session_id
          ? [record]
          : [],
    }),
  call: () => data({ item: { ...record, journey: { legs: [], ivr: [] } } }),
  customerContext: () => data(record.customer),
  cases: () => data({ items: [] }),
  qualifications: () =>
    data({
      items: record.status === 'ended' ? [qualification()] : [],
      agent,
      attendance: record,
      policy: { limits: { voice: 180, whatsapp: 180 } },
    }),
  saveCallObservations: (_, id, note) => {
    record.metadata.attendance_observations = { text: note.text };
    record.lock_version += 1;
    return data({ item: record });
  },
};
