import { describe, it, expect, vi, beforeEach } from 'vitest';
import { mount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import PlaybookDesignPreview from './PlaybookDesignPreview.vue';
import ManualAttendancePanel from './ManualAttendancePanel.vue';

const mocks = vi.hoisted(() => ({
  route: null,
  store: null,
  api: {
    playbookOptions: vi.fn(),
    previewPlaybook: vi.fn(),
    workContext: vi.fn(),
    manualAttendance: vi.fn(),
    portfolioBatch: vi.fn(),
    playbookExecutions: vi.fn(),
  },
}));
vi.mock('vue-router', () => ({ useRoute: () => mocks.route }));
vi.mock('vuex', async original => ({
  ...(await original()),
  useStore: () => mocks.store,
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/jrcRelationship', () => ({ default: mocks.api }));

beforeEach(() => {
  vi.clearAllMocks();
  mocks.route = reactive({ params: { accountId: '12' } });
  mocks.store = { getters: reactive({ getCurrentUserID: 7 }) };
  mocks.api.playbookOptions.mockResolvedValue({
    data: {
      assignments: [[19, 'Authorized customer']],
      contacts: [[71, 'Explicit contact']],
      flows: [
        {
          id: 61,
          name: 'Published flow',
          flow_lock_version: 3,
          flow_digest: 'a'.repeat(64),
        },
      ],
      conversations: [{ id: 41, display_id: 20, contact_id: 71 }],
      business_unit_id: 31,
    },
  });
  mocks.api.previewPlaybook.mockResolvedValue({
    data: { state: 'preview', steps: [] },
  });
  mocks.api.workContext.mockResolvedValue({
    data: {
      contacts: [[71, 'Explicit contact']],
      deals: [{ id: 81, title: 'Native deal' }],
      contracts: [
        {
          id: 91,
          number: 'Native contract',
          products: [[101, 'Native product']],
        },
      ],
    },
  });
  mocks.api.manualAttendance.mockResolvedValue({
    data: { id: 51, status: 'completed' },
  });
});

describe('Reviewed native playbook and attendance UI', () => {
  it('binds an explicitly selected message to the reviewed flow step and omits it again when cleared', async () => {
    const book = reactive({
      name: 'Keyword flow',
      active: false,
      trigger_kind: 'health',
      conditions: [],
      steps: [
        {
          kind: 'flow',
          title: 'Finite keyword step',
          conversation_id: 41,
          contact_id: 71,
          flow_id: 61,
        },
      ],
    });
    mocks.api.playbookOptions.mockResolvedValue({
      data: {
        assignments: [[19, 'Customer']],
        contacts: [[71, 'Contact']],
        conversations: [{ id: 41, display_id: 20, contact_id: 71 }],
        flows: [{ id: 61, keyword_required: true }],
      },
    });
    const wrapper = mount(PlaybookDesignPreview, {
      props: {
        book,
        onUpdateStep: (index, step) => {
          book.steps[index] = step;
        },
      },
    });
    await flushPromises();
    const input = wrapper.get('[data-testid="flow-message-id"]');
    expect(input.attributes('required')).toBeDefined();
    await input.setValue('123');
    expect(book.steps[0].message_id).toBe(123);
    await input.setValue('');
    expect(Object.hasOwn(book.steps[0], 'message_id')).toBe(false);
    await input.setValue('1.5');
    expect(Object.hasOwn(book.steps[0], 'message_id')).toBe(false);
    expect(wrapper.get('[role="alert"]').text()).toContain('INVALID_MESSAGE');
    wrapper.unmount();
  });
  it('uses the exact reviewed source and approvals then verifies persisted native execution without storing the token', async () => {
    const book = {
      id: 9,
      version: 2,
      active: true,
      name: 'Published',
      steps: [{ kind: 'flow', step_key: 'private' }],
    };
    mocks.api.previewPlaybook.mockImplementation(async (account, fields) => ({
      data: {
        state: 'preview',
        matched: true,
        active: true,
        version: 2,
        steps: [
          {
            kind: 'flow',
            step_key: `playbook:9:v2:private:${fields.source_key}`,
            state: 'preview',
            approval_token: 'synthetic-review-token',
            approval_expires_at: new Date(Date.now() + 120000).toISOString(),
          },
        ],
      },
    }));
    mocks.api.portfolioBatch.mockResolvedValue({ data: { updated: 1 } });
    mocks.api.playbookExecutions.mockImplementation(async () => ({
      data: {
        payload: [
          {
            id: 55,
            assignment_id: 19,
            playbook_id: 9,
            version: 2,
            source_key:
              mocks.api.previewPlaybook.mock.calls.at(-1)[1].source_key,
          },
        ],
      },
    }));
    const wrapper = mount(PlaybookDesignPreview, { props: { book } });
    await flushPromises();
    await wrapper.get('[data-testid="preview-assignment"]').setValue('19');
    await flushPromises();
    await wrapper.get('button').trigger('click');
    await flushPromises();
    const origin = mocks.api.previewPlaybook.mock.calls.at(-1)[1].source_key;
    await wrapper.get('[data-testid="run-approved-playbook"]').trigger('click');
    await flushPromises();
    expect(mocks.api.portfolioBatch).toHaveBeenCalledWith('12', [19], {
      operation: 'playbook',
      playbook_id: 9,
      request_id: expect.any(String),
      source_key: origin,
      flow_approvals: {
        [`playbook:9:v2:private:${origin}`]: 'synthetic-review-token',
      },
    });
    expect(mocks.api.playbookExecutions).toHaveBeenCalledWith('12');
    expect(wrapper.emitted('executed')).toEqual([[55]]);
    expect(wrapper.text()).not.toContain('synthetic-review-token');
    expect(wrapper.find('[data-testid="run-approved-playbook"]').exists()).toBe(
      false
    );
    wrapper.unmount();
  });

  it('removes execution approval when the reviewed published step changes', async () => {
    const book = reactive({
      id: 9,
      version: 2,
      active: true,
      name: 'Published',
      steps: [{ kind: 'flow', step_key: 'private' }],
    });
    mocks.api.previewPlaybook.mockResolvedValue({
      data: {
        state: 'preview',
        matched: true,
        active: true,
        version: 2,
        steps: [
          {
            kind: 'flow',
            step_key: 'reviewed-origin',
            approval_token: 'synthetic-review-token',
            approval_expires_at: new Date(Date.now() + 120000).toISOString(),
          },
        ],
      },
    });
    const wrapper = mount(PlaybookDesignPreview, { props: { book } });
    await flushPromises();
    await wrapper.get('select').setValue('19');
    await flushPromises();
    await wrapper.get('button').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-testid="run-approved-playbook"]').exists()).toBe(
      true
    );
    book.steps[0].conversation_id = 99;
    await flushPromises();
    expect(wrapper.find('[data-testid="run-approved-playbook"]').exists()).toBe(
      false
    );
    expect(mocks.api.portfolioBatch).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('does not label an acknowledged run as verified when native execution readback is absent', async () => {
    const book = {
      id: 9,
      version: 2,
      active: true,
      name: 'Published',
      steps: [{ kind: 'flow', step_key: 'private' }],
    };
    mocks.api.previewPlaybook.mockResolvedValue({
      data: {
        state: 'preview',
        matched: true,
        active: true,
        version: 2,
        steps: [
          {
            kind: 'flow',
            step_key: 'reviewed-origin',
            approval_token: 'synthetic-review-token',
            approval_expires_at: new Date(Date.now() + 120000).toISOString(),
          },
        ],
      },
    });
    mocks.api.portfolioBatch.mockResolvedValue({ data: { updated: 1 } });
    mocks.api.playbookExecutions.mockResolvedValue({ data: { payload: [] } });
    const wrapper = mount(PlaybookDesignPreview, { props: { book } });
    await flushPromises();
    await wrapper.get('select').setValue('19');
    await flushPromises();
    await wrapper.get('button').trigger('click');
    await flushPromises();
    await wrapper.get('[data-testid="run-approved-playbook"]').trigger('click');
    await flushPromises();
    expect(wrapper.emitted('executed')).toBeUndefined();
    expect(wrapper.text()).toContain(
      'RELATIONSHIP.PLAYBOOK_PREVIEW.UNVERIFIED'
    );
    wrapper.unmount();
  });

  it.each([undefined, 'invalid-date', '2000-01-01T00:00:00.000Z'])(
    'does not offer execution without a current explicit approval expiry (%s)',
    async expiresAt => {
      mocks.api.previewPlaybook.mockResolvedValue({
        data: {
          matched: true,
          version: 2,
          steps: [
            {
              kind: 'flow',
              step_key: 'reviewed-origin',
              approval_token: 'synthetic-review-token',
              approval_expires_at: expiresAt,
            },
          ],
        },
      });
      const book = {
        id: 9,
        version: 2,
        active: true,
        steps: [{ kind: 'flow' }],
      };
      const wrapper = mount(PlaybookDesignPreview, { props: { book } });
      await flushPromises();
      await wrapper.get('select').setValue('19');
      await flushPromises();
      await wrapper.get('button').trigger('click');
      await flushPromises();
      expect(
        wrapper.find('[data-testid="run-approved-playbook"]').exists()
      ).toBe(false);
      expect(mocks.api.portfolioBatch).not.toHaveBeenCalled();
      wrapper.unmount();
    }
  );

  it('pins the selected publication and explicit customer references without selecting the first contact or conversation', async () => {
    const book = reactive({
      name: 'Native book',
      trigger_kind: 'health',
      active: false,
      conditions: [],
      steps: [
        {
          kind: 'flow',
          title: 'Internal step',
          step_key: 'internal',
          after_days: 0,
        },
      ],
    });
    const wrapper = mount(PlaybookDesignPreview, {
      props: { book },
      attrs: {
        onUpdateStep: (index, step) => {
          book.steps[index] = step;
        },
      },
    });
    await flushPromises();
    await wrapper.get('[data-testid="preview-assignment"]').setValue('19');
    await flushPromises();
    const selects = wrapper.findAll('fieldset select');
    expect(selects[1].element.value).toBe('');
    expect(selects[2].element.value).toBe('');
    await selects[0].setValue('61');
    await selects[1].setValue('71');
    await selects[2].setValue('41');
    await wrapper.get('button').trigger('click');
    await flushPromises();
    expect(mocks.api.previewPlaybook).toHaveBeenCalledWith(
      '12',
      expect.objectContaining({ assignment_id: 19, playbook: book })
    );
    expect(book.steps[0]).toMatchObject({
      flow_id: 61,
      flow_lock_version: 3,
      flow_digest: 'a'.repeat(64),
      contact_id: 71,
      conversation_id: 41,
      business_unit_id: 31,
    });
    expect(mocks.api.manualAttendance).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('discards a delayed preview after its draft changes and lets the changed draft be previewed again', async () => {
    let complete;
    mocks.api.previewPlaybook.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          complete = resolve;
        })
    );
    const book = reactive({
      name: 'Native draft',
      active: false,
      trigger_kind: 'health',
      conditions: [],
      steps: [{ kind: 'action', title: 'Original step', after_days: 0 }],
    });
    const wrapper = mount(PlaybookDesignPreview, { props: { book } });
    await flushPromises();
    await wrapper.get('select').setValue('19');
    await flushPromises();
    await wrapper.get('button').trigger('click');
    book.steps[0].title = 'Changed step';
    await flushPromises();
    complete({
      data: { state: 'preview', reason: 'STALE_PREVIEW', steps: [] },
    });
    await flushPromises();
    expect(wrapper.text()).not.toContain('STALE_PREVIEW');
    expect(wrapper.get('button').attributes('disabled')).toBeUndefined();
    await wrapper.get('button').trigger('click');
    await flushPromises();
    expect(mocks.api.previewPlaybook).toHaveBeenCalledTimes(2);
    wrapper.unmount();
  });

  it('submits selected native attendance references and completion then refreshes after the persisted result', async () => {
    const wrapper = mount(ManualAttendancePanel, {
      props: { assignmentId: 19 },
    });
    await flushPromises();
    const selects = wrapper.findAll('select');
    expect(selects[1].element.value).toBe('');
    expect(selects[2].element.value).toBe('');
    await wrapper.get('input[required]').setValue('Recorded visit');
    await selects[1].setValue('71');
    await selects[2].setValue('81');
    await selects[3].setValue('91');
    await selects[4].setValue('101');
    await wrapper.get('input[type="checkbox"]').setValue(true);
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(mocks.api.manualAttendance).toHaveBeenCalledWith('12', 19, {
      attendance: expect.objectContaining({
        title: 'Recorded visit',
        activity_type: 'visit',
        contact_id: 71,
        deal_id: 81,
        contract_id: 91,
        product_id: 101,
        completed: true,
        request_id: expect.any(String),
      }),
    });
    expect(wrapper.emitted('changed')).toHaveLength(1);
    expect(mocks.api.workContext).toHaveBeenCalledTimes(2);
    expect(wrapper.get('input[required]').element.value).toBe('');
    wrapper.unmount();
  });
});
