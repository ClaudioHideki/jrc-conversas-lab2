import axios from 'axios';
import createAxios from '../../helper/APIHelper';
import structure from '../serviceDeskStructure';
import configuration from '../serviceDeskConfiguration';

vi.mock('../auth', () => ({
  default: {
    hasAuthCookie: () => true,
    getAuthData: () => ({
      'access-token': 'test-session-token',
      'token-type': 'Bearer',
      client: 'test-client',
      uid: 'test-user',
      expiry: '9999999999',
    }),
  },
}));

describe('Service Desk authenticated transport', () => {
  let requests;
  const originalAxios = window.axios;
  beforeEach(() => {
    requests = [];
    window.axios = createAxios(axios);
    window.axios.defaults.adapter = async config => {
      requests.push(config);
      return { data: {}, status: 200, headers: {}, config };
    };
  });
  afterEach(() => {
    window.axios = originalAxios;
  });

  it('sends session headers on structural and configuration reads', async () => {
    await structure.context(1);
    await configuration.list(1, 'statuses', 1);
    expect(requests).toHaveLength(2);
    requests.forEach(request => {
      expect(request.headers.get('access-token')).toBe('test-session-token');
      expect(request.headers.get('client')).toBe('test-client');
      expect(request.headers.get('uid')).toBe('test-user');
    });
  });

  it.each(['create', 'update'])(
    'authenticates %s without losing idempotency headers',
    async action => {
      await structure.save(
        1,
        {
          action,
          resource: 'unit_memberships',
          recordId: 1,
          revision: 'a'.repeat(64),
          reason: 'Authorized test',
          attributes:
            action === 'create'
              ? { unit_id: 1, account_user_id: 15, active: true }
              : { active: false },
        },
        'structure-test'
      );
      await configuration.save(
        1,
        {
          action,
          resource: 'categories',
          unitId: 1,
          recordId: 1,
          revision: 'a'.repeat(64),
          attributes:
            action === 'create'
              ? { name: 'Test', code: 'test', active: true }
              : { active: false },
        },
        'configuration-test'
      );
      expect(requests).toHaveLength(2);
      requests.forEach(request => {
        expect(request.headers.get('access-token')).toBe('test-session-token');
        expect(request.headers.get('Idempotency-Key')).toMatch(/-test$/);
        expect(request.method).toBe(action === 'create' ? 'post' : 'patch');
      });
    }
  );
});
