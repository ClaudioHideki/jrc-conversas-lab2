import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { mount, flushPromises } from '@vue/test-utils';
import { reactive, ref } from 'vue';
import { createI18n } from 'vue-i18n';
import messages from 'widget/i18n/locale/en.json';
import ServiceDeskPortal from '../ServiceDeskPortal.vue';
const mocks = vi.hoisted(() => ({
  store: null,
  identity: vi.fn(),
  hasIdentityProof: vi.fn(),
  services: vi.fn(),
  tickets: vi.fn(),
  knowledge: vi.fn(),
  ticket: vi.fn(),
  create: vi.fn(),
  reply: vi.fn(),
  attachment: vi.fn(),
}));
vi.mock('vuex', () => ({ useStore: () => mocks.store }));
vi.mock('../../api/serviceDesk', () => ({ default: mocks }));
const service = () => ({
  id: '2',
  name: 'Published service',
  description: 'Service description',
  form_fields: [],
  revision: 'a'.repeat(64),
});
const ticket = () => ({
  id: '3',
  title: 'Customer request',
  description: 'Actual symptom',
  status: { name: 'Open', phase: 'open' },
  service_id: '2',
  contract_id: null,
});
const detail = () => ({
  ticket: ticket(),
  notes: [
    {
      id: '4',
      body: 'Published customer update',
      visibility: 'customer',
      attachments: [
        { id: '9', filename: 'Evidence.txt', scan_state: 'unavailable' },
      ],
    },
  ],
  replies: [],
  tasks: [],
  conversations: ['5'],
});
let wrapper;
const render = () => {
  wrapper = mount(ServiceDeskPortal, {
    global: {
      plugins: [
        createI18n({ legacy: false, locale: 'en', messages: { en: messages } }),
      ],
    },
  });
  return wrapper;
};
beforeEach(() => {
  vi.clearAllMocks();
  mocks.store = reactive({
    getters: { 'contacts/getCurrentUser': { id: '6' } },
  });
  mocks.identity.mockReturnValue('native-auth-token-in-test');
  mocks.hasIdentityProof.mockReturnValue(true);
  mocks.services.mockResolvedValue({ services: [] });
  mocks.tickets.mockResolvedValue({ tickets: [ticket()] });
  mocks.knowledge.mockResolvedValue({ articles: [] });
  mocks.ticket.mockResolvedValue(detail());
  window.chatwootWebChannel = { websiteToken: 'test-widget-token' };
});
afterEach(() => {
  wrapper?.unmount();
  wrapper = null;
});
describe('Customer portal remains on the existing verified native widget', () => {
  it('hides the portal and makes no portal request without an in-memory verified SDK proof', async () => {
    mocks.hasIdentityProof.mockReturnValue(false);
    mocks.services.mockResolvedValue({ services: [service()] });
    render();
    await flushPromises();
    expect(wrapper.find('button').exists()).toBe(false);
    expect(mocks.services).not.toHaveBeenCalled();
  });
  it('renders no portal launcher when the server publishes no authorized service', async () => {
    render();
    await flushPromises();
    expect(wrapper.find('button').exists()).toBe(false);
    expect(mocks.tickets).not.toHaveBeenCalled();
  });
  it('immediately removes the launcher and cached ticket content when the in-memory SDK proof is revoked', async () => {
    const proof = ref(Symbol('verified-test-proof'));
    mocks.identity.mockImplementation(() => proof.value);
    mocks.hasIdentityProof.mockImplementation(() => !!proof.value);
    mocks.services.mockResolvedValue({ services: [service()] });
    render();
    await flushPromises();
    await wrapper.get('button').trigger('click');
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(button => button.text().includes('Customer request'))
      .trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('Published customer update');
    proof.value = null;
    await flushPromises();
    expect(wrapper.find('button').exists()).toBe(false);
    expect(wrapper.text()).not.toContain('Published customer update');
    expect(mocks.services).toHaveBeenCalledOnce();
  });
  it('opens real tickets and only shows approved public evidence while scan-unavailable files stay disabled', async () => {
    mocks.services.mockResolvedValue({ services: [service()] });
    render();
    await flushPromises();
    await wrapper.get('button').trigger('click');
    await flushPromises();
    const link = wrapper
      .findAll('button')
      .find(button => button.text().includes('Customer request'));
    await link.trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('Published customer update');
    expect(
      wrapper
        .findAll('button')
        .find(button => button.text().includes('Evidence.txt'))
        .attributes('disabled')
    ).toBeDefined();
    expect(mocks.create).not.toHaveBeenCalled();
  });
  it('rejects an internal interaction in a malformed public projection before displaying its body', async () => {
    mocks.services.mockResolvedValue({ services: [service()] });
    const value = detail();
    value.notes[0].visibility = 'internal';
    value.notes[0].body = 'Private operational content';
    mocks.ticket.mockResolvedValue(value);
    render();
    await flushPromises();
    await wrapper.get('button').trigger('click');
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(button => button.text().includes('Customer request'))
      .trigger('click');
    await flushPromises();
    expect(wrapper.text()).not.toContain('Private operational content');
  });
  it('creates with the selected published version, native request key and an independent readback before reporting success', async () => {
    mocks.services.mockResolvedValue({ services: [service()] });
    mocks.create.mockResolvedValue({
      applied: true,
      ticket: ticket(),
      message_id: '8',
      conversation_id: '5',
    });
    render();
    await flushPromises();
    await wrapper.get('button').trigger('click');
    await flushPromises();
    await wrapper.get('select').setValue('2');
    await wrapper.get('input[maxlength="255"]').setValue('Customer request');
    await wrapper.get('textarea[maxlength="20000"]').setValue('Actual symptom');
    await wrapper.get('[data-testid="portal-create"]').trigger('submit');
    await flushPromises();
    expect(mocks.create).toHaveBeenCalledOnce();
    expect(mocks.create.mock.calls[0][1]).toEqual({
      service_id: '2',
      service_revision: 'a'.repeat(64),
      title: 'Customer request',
      description: 'Actual symptom',
      service_fields: {},
    });
    expect(mocks.create.mock.calls[0][3]).toMatch(/^[a-f0-9-]{36}$/);
    expect(mocks.ticket).toHaveBeenCalled();
    expect(wrapper.text()).toContain(messages.SERVICE_DESK.saved);
  });
  it('clears rendered evidence when native identity changes or current authorization is denied', async () => {
    mocks.services.mockResolvedValue({ services: [service()] });
    render();
    await flushPromises();
    await wrapper.get('button').trigger('click');
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(button => button.text().includes('Customer request'))
      .trigger('click');
    await flushPromises();
    mocks.reply.mockRejectedValue({ response: { status: 403 } });
    await wrapper.get('textarea').setValue('Customer reply');
    await wrapper.get('[data-testid="portal-reply"]').trigger('submit');
    await flushPromises();
    expect(wrapper.text()).not.toContain('Published customer update');
    mocks.services.mockResolvedValue({ services: [] });
    mocks.store.getters['contacts/getCurrentUser'] = { id: '99' };
    await flushPromises();
    expect(wrapper.find('button').exists()).toBe(false);
  });
  it('shows native public knowledge before the creation form and sends separate bounded search terms for knowledge and ticket history', async () => {
    mocks.services.mockResolvedValue({ services: [service()] });
    mocks.knowledge.mockResolvedValue({
      articles: [
        {
          id: '8',
          title: 'Published solution',
          description: 'Read first',
          path: '/hc/support/articles/solution',
        },
      ],
    });
    render();
    await flushPromises();
    await wrapper.get('button').trigger('click');
    await flushPromises();
    const article = wrapper.get('a[href="/hc/support/articles/solution"]');
    expect(article.text()).toContain('Published solution');
    expect(article.attributes('rel')).toBe('noopener noreferrer');
    expect(
      wrapper.element
        .querySelector('a')
        .compareDocumentPosition(
          wrapper.get('[data-testid="portal-create"]').element
        )
    ).toBe(Node.DOCUMENT_POSITION_FOLLOWING);
    await wrapper
      .get('[data-testid="portal-knowledge"] input')
      .setValue('password');
    await wrapper.get('[data-testid="portal-knowledge"]').trigger('submit');
    await flushPromises();
    expect(mocks.knowledge.mock.lastCall[1]).toBe('password');
    await wrapper
      .get('[data-testid="portal-history"] input')
      .setValue('request');
    await wrapper.get('[data-testid="portal-history"]').trigger('submit');
    await flushPromises();
    expect(mocks.tickets.mock.lastCall[2]).toBe('request');
    expect(mocks.create).not.toHaveBeenCalled();
  });
  it('requires an explicit eligible contract and verifies that exact contract through an independent readback', async () => {
    mocks.services.mockResolvedValue({
      services: [
        {
          ...service(),
          contract_required: true,
          contracts: [
            { id: '11', name: 'First contract' },
            { id: '12', name: 'Chosen contract' },
          ],
        },
      ],
    });
    mocks.create.mockResolvedValue({
      applied: true,
      ticket: { ...ticket(), contract_id: '12' },
    });
    mocks.ticket.mockResolvedValue({
      ...detail(),
      ticket: { ...ticket(), contract_id: '12' },
    });
    render();
    await flushPromises();
    await wrapper.get('button').trigger('click');
    await flushPromises();
    const form = wrapper.get('[data-testid="portal-create"]');
    await form.get('select').setValue('2');
    await form.get('input[maxlength="255"]').setValue('Customer request');
    await form.get('textarea').setValue('Actual symptom');
    expect(
      form.get('button[type="submit"]').attributes('disabled')
    ).toBeDefined();
    await form.trigger('submit');
    expect(mocks.create).not.toHaveBeenCalled();
    await form.findAll('select')[1].setValue('12');
    await form.trigger('submit');
    await flushPromises();
    expect(mocks.create.mock.lastCall[1].contract_id).toBe('12');
    expect(wrapper.text()).toContain(messages.SERVICE_DESK.saved);
  });
  it('does not report a creation as saved when the readback silently binds the first contract instead', async () => {
    mocks.services.mockResolvedValue({
      services: [
        {
          ...service(),
          contract_required: true,
          contracts: [
            { id: '11', name: 'First contract' },
            { id: '12', name: 'Chosen contract' },
          ],
        },
      ],
    });
    mocks.create.mockResolvedValue({
      applied: true,
      ticket: { ...ticket(), contract_id: '12' },
    });
    mocks.ticket.mockResolvedValue({
      ...detail(),
      ticket: { ...ticket(), contract_id: '11' },
    });
    render();
    await flushPromises();
    await wrapper.get('button').trigger('click');
    await flushPromises();
    const form = wrapper.get('[data-testid="portal-create"]');
    await form.get('select').setValue('2');
    await form.findAll('select')[1].setValue('12');
    await form.get('input[maxlength="255"]').setValue('Customer request');
    await form.get('textarea').setValue('Actual symptom');
    await form.trigger('submit');
    await flushPromises();
    expect(wrapper.text()).not.toContain(messages.SERVICE_DESK.saved);
    expect(wrapper.find('[data-testid="portal-create"]').exists()).toBe(true);
  });
  it('does not choose the first conversation when multiple authorized conversations are linked', async () => {
    mocks.services.mockResolvedValue({ services: [service()] });
    mocks.ticket.mockResolvedValue({ ...detail(), conversations: ['5', '10'] });
    render();
    await flushPromises();
    await wrapper.get('button').trigger('click');
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(button => button.text().includes('Customer request'))
      .trigger('click');
    await flushPromises();
    const form = wrapper.get('[data-testid="portal-reply"]');
    expect(form.get('select').element.value).toBe('');
    await form.get('textarea').setValue('Explicit customer reply');
    await form.trigger('submit');
    expect(mocks.reply).not.toHaveBeenCalled();
    mocks.reply.mockResolvedValue({ applied: true, message_id: '21' });
    mocks.ticket.mockResolvedValue({
      ...detail(),
      conversations: ['5', '10'],
      replies: [{ id: '21', body: 'Explicit customer reply', attachments: [] }],
    });
    await form.get('select').setValue('10');
    await form.trigger('submit');
    await flushPromises();
    expect(mocks.reply.mock.lastCall[3]).toBe('10');
    expect(wrapper.text()).toContain(messages.SERVICE_DESK.saved);
  });
  it('discards a knowledge response from a revoked identity instead of caching customer content', async () => {
    const proof = ref(Symbol('verified-test-proof'));
    mocks.identity.mockImplementation(() => proof.value);
    mocks.hasIdentityProof.mockImplementation(() => !!proof.value);
    mocks.services.mockResolvedValue({ services: [service()] });
    render();
    await flushPromises();
    await wrapper.get('button').trigger('click');
    await flushPromises();
    let complete;
    mocks.knowledge.mockReturnValueOnce(
      new Promise(resolve => {
        complete = resolve;
      })
    );
    await wrapper.get('[data-testid="portal-knowledge"]').trigger('submit');
    proof.value = null;
    await flushPromises();
    complete({
      articles: [
        {
          id: '8',
          title: 'Old customer knowledge',
          description: '',
          path: '/hc/support/articles/old',
        },
      ],
    });
    await flushPromises();
    expect(wrapper.text()).not.toContain('Old customer knowledge');
    expect(wrapper.find('button').exists()).toBe(false);
  });
  it('renders actual SLA snapshots, delivery evidence and native survey links from the customer projection', async () => {
    const time = '2026-10-08T12:00:00Z';
    mocks.services.mockResolvedValue({ services: [service()] });
    mocks.ticket.mockResolvedValue({
      ...detail(),
      sla: [
        {
          kind: 'resolution',
          state: 'running',
          time_basis: 'business',
          budget_seconds: 3600,
          elapsed_seconds: 1200,
          remaining_seconds: 2400,
          consumed_percent: 33.3,
          breached: false,
          due_at: time,
          observed_at: time,
          achieved_at: null,
          timezone: 'America/Sao_Paulo',
        },
      ],
      notification_history: [
        {
          id: '18',
          channel: 'email',
          state: 'sent',
          attempt_number: 1,
          created_at: time,
          updated_at: time,
          sent_at: time,
          delivered_at: null,
          body: 'Public receipt',
        },
      ],
      surveys: [
        {
          id: '19',
          kind: 'csat',
          expires_at: '2026-11-08T12:00:00Z',
          path: '/jrc/relacionamento/pesquisas/signed-token',
        },
      ],
    });
    render();
    await flushPromises();
    await wrapper.get('button').trigger('click');
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(button => button.text().includes('Customer request'))
      .trigger('click');
    await flushPromises();
    expect(wrapper.get('[data-testid="portal-sla"]').text()).toContain('33.3%');
    expect(wrapper.get('[data-testid="portal-sla"]').text()).toContain(
      'America/Sao_Paulo'
    );
    expect(
      wrapper.get('[data-testid="portal-notifications"]').text()
    ).toContain('Public receipt');
    expect(
      wrapper.get('[data-testid="portal-notifications"]').text()
    ).not.toContain('SERVICE_DESK.delivered_at');
    expect(
      wrapper.get('[data-testid="portal-surveys"] a').attributes('href')
    ).toBe('/jrc/relacionamento/pesquisas/signed-token');
    expect(mocks.create).not.toHaveBeenCalled();
    expect(mocks.reply).not.toHaveBeenCalled();
  });
});
