import { describe, it, expect, beforeEach, vi } from 'vitest';
import Contacts from '../contacts';
import ServiceDesk from '../serviceDesk';
import { beginPortalIdentity } from '../../helpers/serviceDeskIdentityProof';

const mocks = vi.hoisted(() => ({
  defaults: { headers: { common: { 'X-Auth-Token': 'native-token-in-test' } } },
  get: vi.fn(),
  post: vi.fn(),
  patch: vi.fn(),
}));
vi.mock('widget/helpers/axios', () => ({ API: mocks }));
const testProof = 'a'.repeat(64);
const testIdentifier = 'verified-customer-in-test';

beforeEach(() => {
  vi.clearAllMocks();
  beginPortalIdentity();
  mocks.defaults.headers.common = { 'X-Auth-Token': 'native-token-in-test' };
  mocks.patch.mockResolvedValue({ data: { id: 1 } });
  mocks.get.mockResolvedValue({ data: { services: [] } });
});

describe('Service Desk uses only a fresh native SDK identity proof held in memory', () => {
  it('sends the proof only to Service Desk after successful setUser and never mutates shared native headers or storage', async () => {
    const local = vi.spyOn(Storage.prototype, 'setItem');
    await Contacts.setUser(testIdentifier, { identifier_hash: testProof });
    expect(ServiceDesk.hasIdentityProof()).toBe(true);
    await ServiceDesk.services('widget-in-test');
    expect(mocks.get.mock.calls[0][1].headers).toEqual({
      'X-Service-Desk-Identifier': testIdentifier,
      'X-Service-Desk-Identity-Token': testProof,
    });
    expect(mocks.defaults.headers.common).toEqual({
      'X-Auth-Token': 'native-token-in-test',
    });
    expect(local).not.toHaveBeenCalled();
    await Contacts.get();
    expect(mocks.get.mock.calls[1]).toHaveLength(1);
    local.mockRestore();
  });

  it('requires the native token returned by setUser when the identified session changes', async () => {
    mocks.patch.mockResolvedValue({
      data: { id: 2, widget_auth_token: 'new-native-token-in-test' },
    });
    await Contacts.setUser(testIdentifier, { identifier_hash: testProof });
    expect(ServiceDesk.hasIdentityProof()).toBe(false);
    mocks.defaults.headers.common['X-Auth-Token'] = 'new-native-token-in-test';
    expect(ServiceDesk.hasIdentityProof()).toBe(true);
    await ServiceDesk.services('widget-in-test');
    mocks.defaults.headers.common['X-Auth-Token'] = 'different-native-token';
    expect(ServiceDesk.hasIdentityProof()).toBe(false);
    expect(() => ServiceDesk.services('widget-in-test')).toThrow(
      'Verified customer identity required'
    );
    expect(mocks.get).toHaveBeenCalledOnce();
  });

  it('keeps legacy setUser usable without HMAC while denying the new portal and clears a proof on failed reidentification', async () => {
    delete mocks.defaults.headers.common['X-Auth-Token'];
    expect(ServiceDesk.hasIdentityProof()).toBe(false);
    const response = await Contacts.setUser(testIdentifier);
    expect(response.data.id).toBe(1);
    mocks.defaults.headers.common['X-Auth-Token'] = 'native-token-in-test';
    await Contacts.setUser(testIdentifier, {});
    expect(ServiceDesk.hasIdentityProof()).toBe(false);
    expect(() => ServiceDesk.tickets('widget-in-test')).toThrow();
    await Contacts.setUser(testIdentifier, { identifier_hash: testProof });
    mocks.patch.mockRejectedValue({ response: { status: 401 } });
    await expect(
      Contacts.setUser('other-customer', { identifier_hash: testProof })
    ).rejects.toEqual({ response: { status: 401 } });
    expect(ServiceDesk.hasIdentityProof()).toBe(false);
    expect(mocks.get).not.toHaveBeenCalled();
  });

  it('clears the portal proof before an email-only native update that can merge identities, while keeping that update unchanged', async () => {
    await Contacts.setUser(testIdentifier, { identifier_hash: testProof });
    await Contacts.update({ email: 'other-customer@example.test' });
    expect(ServiceDesk.hasIdentityProof()).toBe(false);
    expect(mocks.patch.mock.calls[1]).toEqual([
      '/api/v1/widget/contact',
      { email: 'other-customer@example.test' },
    ]);
    expect(() => ServiceDesk.tickets('widget-in-test')).toThrow();
    expect(mocks.get).not.toHaveBeenCalled();
  });

  it('ignores an older successful setUser response after another identity attempt starts', async () => {
    let complete;
    mocks.patch.mockReturnValueOnce(
      new Promise(resolve => {
        complete = resolve;
      })
    );
    const old = Contacts.setUser(testIdentifier, {
      identifier_hash: testProof,
    });
    await Contacts.setUser('new-customer', { identifier_hash: 'b'.repeat(64) });
    complete({ data: { id: 1 } });
    await old;
    await ServiceDesk.services('widget-in-test');
    expect(
      mocks.get.mock.calls[0][1].headers['X-Service-Desk-Identifier']
    ).toBe('new-customer');
  });
  it('uses the same verified per-request identity for knowledge and ticket searches without changing native shared headers', async () => {
    await Contacts.setUser(testIdentifier, { identifier_hash: testProof });
    await ServiceDesk.knowledge('widget-in-test', 'Published answer');
    await ServiceDesk.tickets('widget-in-test', undefined, 'History term');
    expect(
      mocks.get.mock.calls.map(call => [call[0], call[1].params.q])
    ).toEqual([
      ['/api/v1/widget/service_desk/knowledge', 'Published answer'],
      ['/api/v1/widget/service_desk/tickets', 'History term'],
    ]);
    mocks.get.mock.calls.forEach(call =>
      expect(call[1].headers).toEqual({
        'X-Service-Desk-Identifier': testIdentifier,
        'X-Service-Desk-Identity-Token': testProof,
      })
    );
    expect(mocks.defaults.headers.common).toEqual({
      'X-Auth-Token': 'native-token-in-test',
    });
    expect(() =>
      ServiceDesk.knowledge('widget-in-test', 'x'.repeat(201))
    ).toThrow('Invalid portal search');
    beginPortalIdentity();
    expect(() => ServiceDesk.knowledge('widget-in-test', '')).toThrow(
      'Verified customer identity required'
    );
    expect(mocks.get).toHaveBeenCalledTimes(2);
  });
});
