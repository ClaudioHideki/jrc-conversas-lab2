import { mount, flushPromises } from '@vue/test-utils';
import OnboardingFlow from '../OnboardingFlow.vue';
import { createJrcBrokerApi } from 'dashboard/api/jrcBroker';

vi.mock('dashboard/api/jrcBroker', () => ({ createJrcBrokerApi: vi.fn() }));
const wizardResources = {
  providers: [{ id: 'provider', name: 'Demo provider' }],
  instances: [{ id: 'session', name: 'Conexão técnica' }],
  agents: [
    { id: 1, name: 'Ágata Demo' },
    { id: 2, name: 'Bruno Demo' },
  ],
  connections: [
    { integrationId: 'existing', name: 'Suporte técnico', inboxId: 2 },
    { integrationId: 'other', name: 'Comercial', inboxId: 3 },
  ],
};
let api;
let wrapper;
beforeEach(() => {
  api = {
    resources: vi.fn().mockResolvedValue(wizardResources),
    operations: vi.fn().mockResolvedValue({ data: [] }),
    create: vi.fn(),
    adopt: vi.fn(),
    operation: vi.fn(),
  };
  createJrcBrokerApi.mockReturnValue(api);
});
afterEach(() => wrapper?.unmount());

const prepareCreateReview = async () => {
  await wrapper.get('[data-testid="setup-type-create"]').setValue();
  await wrapper.get('[data-testid="onboarding-next"]').trigger('click');
  await wrapper.get('[data-testid="onboarding-name"]').setValue('New support');
  await wrapper.get('[data-testid="instance-session"]').setValue();
  await wrapper.get('[data-testid="onboarding-next"]').trigger('click');
  await wrapper.get('[data-testid="onboarding-next"]').trigger('click');
};

it('shows only the current wizard stage and never mutates on Next or Back', async () => {
  api.resources.mockResolvedValue(wizardResources);
  wrapper = mount(OnboardingFlow, {
    props: { accountId: 1 },
    global: { stubs: { ConnectionPanel: true, RouterLink: true } },
  });
  await flushPromises();
  expect(wrapper.find('[data-testid="onboarding-step-1"]').exists()).toBe(true);
  expect(wrapper.find('[data-testid="onboarding-name"]').exists()).toBe(false);
  expect(wrapper.find('[data-testid="onboarding-agent-search"]').exists()).toBe(
    false
  );
  await wrapper.get('[data-testid="setup-type-create"]').setValue();
  await wrapper.get('[data-testid="onboarding-next"]').trigger('click');
  await wrapper.get('[data-testid="onboarding-name"]').setValue('New support');
  await wrapper.get('[data-testid="instance-session"]').setValue();
  await wrapper.get('[data-testid="onboarding-next"]').trigger('click');
  expect(wrapper.find('[data-testid="onboarding-name"]').exists()).toBe(false);
  await wrapper.get('[data-testid="agent-1"]').setValue(true);
  await wrapper
    .get('[data-testid="onboarding-agent-search"]')
    .setValue('BRUNO');
  expect(wrapper.find('[data-testid="agent-1"]').exists()).toBe(false);
  await wrapper.get('[data-testid="onboarding-next"]').trigger('click');
  expect(wrapper.get('[data-testid="onboarding-review"]').text()).toContain(
    'Ágata Demo'
  );
  expect(wrapper.get('[data-testid="onboarding-review"]').text()).toContain(
    'New support'
  );
  expect(api.create).not.toHaveBeenCalled();
  expect(api.adopt).not.toHaveBeenCalled();
  await wrapper.get('[data-testid="onboarding-back"]').trigger('click');
  await wrapper.get('[data-testid="onboarding-back"]').trigger('click');
  expect(wrapper.get('[data-testid="onboarding-name"]').element.value).toBe(
    'New support'
  );
  expect(wrapper.get('[data-testid="instance-session"]').element.checked).toBe(
    true
  );
});

it('searches authorized existing inbox names without accents and adopts only from final review', async () => {
  api.resources.mockResolvedValue(wizardResources);
  api.adopt = vi.fn().mockResolvedValue({ inboxId: 2 });
  wrapper = mount(OnboardingFlow, {
    props: { accountId: 1 },
    global: { stubs: { ConnectionPanel: true, RouterLink: true } },
  });
  await flushPromises();
  await wrapper.get('[data-testid="setup-type-adopt"]').setValue();
  await wrapper.get('[data-testid="onboarding-next"]').trigger('click');
  await wrapper
    .get('[data-testid="onboarding-inbox-search"]')
    .setValue('TECNICO');
  expect(wrapper.find('[data-testid="adopt-existing"]').exists()).toBe(true);
  expect(wrapper.find('[data-testid="adopt-other"]').exists()).toBe(false);
  expect(wrapper.find('[data-testid="onboarding-name"]').exists()).toBe(false);
  await wrapper.get('[data-testid="adopt-existing"]').setValue();
  await wrapper.get('[data-testid="onboarding-next"]').trigger('click');
  expect(wrapper.find('[data-testid="agent-1"]').exists()).toBe(false);
  await wrapper.get('[data-testid="onboarding-next"]').trigger('click');
  expect(wrapper.get('[data-testid="onboarding-review"]').text()).toContain(
    'Suporte técnico'
  );
  expect(api.adopt).not.toHaveBeenCalled();
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(api.adopt).toHaveBeenCalledWith('existing', expect.any(AbortSignal));
  expect(api.create).not.toHaveBeenCalled();
});

it('clears empty wizard searches and keeps selected agents across filtering', async () => {
  api.resources.mockResolvedValue(wizardResources);
  wrapper = mount(OnboardingFlow, {
    props: { accountId: 1 },
    global: { stubs: { RouterLink: true } },
  });
  await flushPromises();
  await wrapper.get('[data-testid="setup-type-create"]').setValue();
  await wrapper.get('[data-testid="onboarding-next"]').trigger('click');
  await wrapper.get('[data-testid="onboarding-name"]').setValue('Support');
  await wrapper.get('[data-testid="instance-session"]').setValue();
  await wrapper.get('[data-testid="onboarding-next"]').trigger('click');
  await wrapper.get('[data-testid="agent-1"]').setValue(true);
  await wrapper
    .get('[data-testid="onboarding-agent-search"]')
    .setValue('not a name');
  expect(wrapper.get('[data-testid="agent-search-empty"]').exists()).toBe(true);
  await wrapper.get('[data-testid="clear-agent-search"]').trigger('click');
  expect(wrapper.get('[data-testid="agent-1"]').element.checked).toBe(true);
  expect(wrapper.findAll('input[type="checkbox"]')).toHaveLength(2);
  expect(api.create).not.toHaveBeenCalled();
});

it('adopts an existing connection without creating an onboarding', async () => {
  api.resources.mockResolvedValue({
    providers: [],
    instances: [],
    agents: [],
    connections: [
      { integrationId: 'existing', name: 'Existing inbox', inboxId: 2 },
    ],
  });
  api.adopt = vi.fn().mockResolvedValue({ inboxId: 2 });
  wrapper = mount(OnboardingFlow, {
    props: { accountId: 1 },
    global: { stubs: { ConnectionPanel: true, RouterLink: true } },
  });
  await flushPromises();
  await wrapper.get('[data-testid="setup-type-adopt"]').setValue();
  await wrapper.get('[data-testid="onboarding-next"]').trigger('click');
  await wrapper.get('[data-testid="adopt-existing"]').setValue();
  await wrapper.get('[data-testid="onboarding-next"]').trigger('click');
  await wrapper.get('[data-testid="onboarding-next"]').trigger('click');
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(api.adopt).toHaveBeenCalledWith('existing', expect.any(AbortSignal));
  expect(api.create).not.toHaveBeenCalled();
  expect(wrapper.find('connection-panel-stub').exists()).toBe(true);
});

it('waits for the Rails binding check before displaying a previously completed connection', async () => {
  const completed = {
    operationId: 'synthetic-operation',
    state: 'SUCCEEDED',
    stage: 'DONE',
    inboxId: 2,
  };
  api.operations.mockResolvedValue({ data: [completed] });
  let finish;
  api.operation.mockImplementation(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  wrapper = mount(OnboardingFlow, {
    props: { accountId: 1 },
    global: { stubs: { RouterLink: true, ConnectionPanel: true } },
  });
  await flushPromises();
  await wrapper
    .findAll('button')
    .find(button => button.text() === 'Resume')
    .trigger('click');
  await flushPromises();
  expect(wrapper.find('connection-panel-stub').exists()).toBe(false);
  finish(completed);
  await flushPromises();
  expect(wrapper.find('connection-panel-stub').exists()).toBe(true);
});

it('allows correcting a rejected request instead of permanently retrying the invalid body', async () => {
  api.create.mockRejectedValue({ response: { status: 400 } });
  wrapper = mount(OnboardingFlow, {
    props: { accountId: 1 },
    global: { stubs: { RouterLink: true } },
  });
  await flushPromises();
  await prepareCreateReview();
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(wrapper.get('fieldset').attributes('disabled')).toBeUndefined();
  const originalKey = api.create.mock.calls[0][1];
  await wrapper.get('[data-testid="onboarding-back"]').trigger('click');
  await wrapper.get('[data-testid="onboarding-back"]').trigger('click');
  await wrapper
    .get('[data-testid="onboarding-name"]')
    .setValue('Corrected support');
  await wrapper.get('[data-testid="onboarding-next"]').trigger('click');
  await wrapper.get('[data-testid="onboarding-next"]').trigger('click');
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(api.create.mock.calls[1][0].name).toBe('Corrected support');
  expect(api.create.mock.calls[1][1]).not.toBe(originalKey);
});

it('treats early form submission as navigation and reviews a new connection provider before creating', async () => {
  wrapper = mount(OnboardingFlow, {
    props: { accountId: 1 },
    global: { stubs: { RouterLink: true } },
  });
  await flushPromises();
  await wrapper.get('[data-testid="setup-type-create"]').setValue();
  await wrapper.get('form').trigger('submit');
  expect(api.create).not.toHaveBeenCalled();
  await wrapper.get('[data-testid="onboarding-name"]').setValue('New inbox');
  await wrapper.get('[data-testid="onboarding-source"]').setValue('NEW');
  await wrapper
    .get('[data-testid="onboarding-instance-name"]')
    .setValue('New WhatsApp');
  await wrapper.get('[data-testid="onboarding-provider"]').setValue('provider');
  await wrapper.get('[data-testid="onboarding-next"]').trigger('click');
  await wrapper.get('[data-testid="agent-2"]').setValue(true);
  await wrapper.get('[data-testid="onboarding-next"]').trigger('click');
  expect(wrapper.get('[data-testid="onboarding-review"]').text()).toContain(
    'Demo provider'
  );
  expect(api.create).not.toHaveBeenCalled();
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(api.create).toHaveBeenCalledWith(
    {
      name: 'New inbox',
      source: {
        kind: 'NEW',
        instanceName: 'New WhatsApp',
        providerAccountId: 'provider',
      },
      agentIds: [2],
      replaceExistingWebhook: false,
    },
    expect.any(String),
    expect.any(AbortSignal)
  );
});

it('keeps a single intent during double submit and retries the same intent after uncertainty', async () => {
  let fail;
  api.create.mockImplementation(
    () =>
      new Promise((_, reject) => {
        fail = reject;
      })
  );
  wrapper = mount(OnboardingFlow, {
    props: { accountId: 1 },
    global: { stubs: { RouterLink: true } },
  });
  await flushPromises();
  await prepareCreateReview();
  await wrapper.get('form').trigger('submit');
  await wrapper.get('form').trigger('submit');
  expect(api.create).toHaveBeenCalledTimes(1);
  const [body, key] = api.create.mock.calls[0];
  fail(new Error('timeout'));
  await flushPromises();
  await wrapper.get('form').trigger('submit');
  expect(api.create).toHaveBeenCalledTimes(2);
  expect(api.create.mock.calls[1].slice(0, 2)).toEqual([body, key]);
  fail(new Error('timeout'));
  await flushPromises();
});

it('resumes a persisted operation through GET and does not create a second inbox', async () => {
  const operation = {
    operationId: 'synthetic-operation',
    state: 'UNKNOWN',
    stage: 'LINK_INBOX',
  };
  api.operations.mockResolvedValue({ data: [operation] });
  api.operation.mockResolvedValue(operation);
  wrapper = mount(OnboardingFlow, {
    props: { accountId: 1 },
    global: { stubs: { RouterLink: true } },
  });
  await flushPromises();
  const resume = wrapper
    .findAll('button')
    .find(button => button.text() === 'Resume');
  await resume.trigger('click');
  await flushPromises();
  expect(api.operation).toHaveBeenCalledWith(
    operation.operationId,
    expect.any(AbortSignal)
  );
  expect(api.create).not.toHaveBeenCalled();
  expect(wrapper.text()).toContain('Needs reconciliation');
});
