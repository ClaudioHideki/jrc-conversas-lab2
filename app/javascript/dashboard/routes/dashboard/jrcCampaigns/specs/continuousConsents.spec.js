import { flushPromises, mount } from '@vue/test-utils';
import ConsentPanel from '../components/ConsentPanel.vue';
import api from 'dashboard/api/jrcCampaigns';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key, locale: { value: 'pt_BR' } }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/jrcCampaigns', () => ({
  default: {
    consents: vi.fn(),
    createConsent: vi.fn(),
    revokeConsent: vi.fn(),
  },
}));

describe('Continuous recipient consent', () => {
  let wrapper;
  beforeEach(() => {
    vi.clearAllMocks();
    api.consents.mockResolvedValue({ data: [] });
    api.createConsent.mockResolvedValue({ data: { id: 5 } });
    api.revokeConsent.mockResolvedValue({});
    wrapper = mount(ConsentPanel, {
      global: {
        stubs: { TestAuthorizationPanel: true, ConsentImportPanel: true },
      },
    });
  });
  afterEach(() => wrapper.unmount());

  it('shows continuous consent first and keeps single-test permission optional', () => {
    expect(wrapper.find('h2').text()).toBe(
      'JRC_CAMPAIGNS.CONSENT_SCREEN.TITLE'
    );
    expect(wrapper.find('details').attributes('open')).toBeUndefined();
  });

  it('requires explicit confirmation of recurring tests and campaigns', async () => {
    await wrapper.vm.openEditor('add');
    await wrapper.find('input[type="tel"]').setValue('5511999999000');
    await wrapper
      .find('textarea')
      .setValue('Synthetic recipient permits recurring tests and campaigns.');
    expect(
      wrapper.find('button[type="submit"]').attributes('disabled')
    ).toBeDefined();
    await wrapper.find('form').trigger('submit');
    expect(api.createConsent).not.toHaveBeenCalled();
  });

  it('records one continuous authorization rather than a single-test grant', async () => {
    await wrapper.vm.openEditor('add');
    await wrapper.find('input[type="tel"]').setValue('5511999999000');
    await wrapper
      .find('textarea')
      .setValue('Synthetic recipient permits recurring tests and campaigns.');
    await wrapper.find('input[type="checkbox"]').setValue(true);
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(api.createConsent).toHaveBeenCalledExactlyOnceWith({
      phone_number: '5511999999000',
      evidence: 'Synthetic recipient permits recurring tests and campaigns.',
      operator_confirmed: true,
      supersedes_id: null,
    });
    expect(wrapper.find('form').exists()).toBe(false);
    expect(wrapper.vm.form.operator_confirmed).toBe(false);
  });

  it('asks for fresh evidence when confirming a historical phone without altering it', async () => {
    api.consents.mockResolvedValue({
      data: [
        {
          id: 2,
          phone_number: '+5511999999000',
          evidence: 'Original evidence',
          purpose: null,
        },
      ],
    });
    await wrapper.vm.load();
    await wrapper
      .findAll('button')
      .find(
        button => button.text() === 'JRC_CAMPAIGNS.CONSENT_SCREEN.RECONFIRM'
      )
      .trigger('click');
    expect(wrapper.find('input[type="tel"]').element.value).toBe(
      '+5511999999000'
    );
    expect(wrapper.find('textarea').element.value).toBe('');
    expect(wrapper.find('input[type="checkbox"]').element.checked).toBe(false);
    expect(wrapper.text()).toContain('Original evidence');
    expect(api.createConsent).not.toHaveBeenCalled();
    await wrapper
      .find('textarea')
      .setValue('New explicit holder confirmation with date and reference.');
    await wrapper.find('input[type="checkbox"]').setValue(true);
    await wrapper.find('form').trigger('submit');
    expect(api.createConsent.mock.calls[0][0].supersedes_id).toBe(2);
  });

  it('requires confirmation again if the destination changes', async () => {
    await wrapper.vm.openEditor('add');
    await wrapper.find('input[type="tel"]').setValue('5511999999000');
    await wrapper.find('input[type="checkbox"]').setValue(true);
    await wrapper.find('input[type="tel"]').setValue('5511999999001');
    expect(wrapper.find('input[type="checkbox"]').element.checked).toBe(false);
  });

  it('shows continuous and historical scope explicitly and permits revocation', async () => {
    api.consents.mockResolvedValue({
      data: [
        {
          id: 5,
          phone_number: '+5511999999000',
          evidence: 'New recurring scope',
          purpose: 'whatsapp_campaigns',
          supersedes_id: 2,
        },
        {
          id: 2,
          phone_number: '+5511999999000',
          evidence: 'Old evidence',
          revoked_at: '2026-10-20',
          superseded_by_id: 5,
        },
      ],
    });
    await wrapper.vm.load();
    expect(wrapper.text()).toContain(
      'JRC_CAMPAIGNS.GOVERNANCE.CONTINUOUS_ACTIVE'
    );
    expect(wrapper.text()).toContain('JRC_CAMPAIGNS.GOVERNANCE.SUPERSEDED');
    const revokeButtons = wrapper
      .findAll('button')
      .filter(button => button.text() === 'JRC_CAMPAIGNS.GOVERNANCE.REVOKE');
    expect(revokeButtons).toHaveLength(1);
    await revokeButtons[0].trigger('click');
    expect(api.revokeConsent).toHaveBeenCalledExactlyOnceWith(5);
  });

  it('opens only the selected action and discards confirmation when cancelling', async () => {
    expect(wrapper.find('form').exists()).toBe(false);
    expect(wrapper.findComponent({ name: 'ConsentImportPanel' }).exists()).toBe(
      false
    );
    await wrapper.vm.openEditor('add');
    await wrapper.find('input[type="tel"]').setValue('5511999999000');
    await wrapper.find('input[type="checkbox"]').setValue(true);
    await wrapper.vm.closeEditor();
    expect(wrapper.find('form').exists()).toBe(false);
    await wrapper.vm.openEditor('add');
    expect(wrapper.find('input[type="checkbox"]').element.checked).toBe(false);
    expect(wrapper.find('input[type="tel"]').element.value).toBe('');
    await wrapper.vm.openEditor('import');
    expect(wrapper.find('form').exists()).toBe(false);
    expect(wrapper.findComponent({ name: 'ConsentImportPanel' }).exists()).toBe(
      true
    );
    expect(api.createConsent).not.toHaveBeenCalled();
  });

  it('filters active, pending and historical records and searches formatted phones', async () => {
    api.consents.mockResolvedValue({
      data: [
        {
          id: 1,
          phone_number: '+5511999999000',
          purpose: 'whatsapp_campaigns',
        },
        { id: 2, phone_number: '+5511999999001', purpose: null },
        {
          id: 3,
          phone_number: '+5511999999002',
          purpose: 'whatsapp_campaigns',
          revoked_at: '2026-10-20T12:00:00Z',
        },
      ],
    });
    await wrapper.vm.load();
    expect(wrapper.findAll('article')).toHaveLength(3);
    await wrapper
      .findAll('[aria-pressed]')
      .find(button => button.text().includes('CONSENT_SCREEN.ACTIVE'))
      .trigger('click');
    expect(wrapper.findAll('article')).toHaveLength(1);
    expect(wrapper.find('article').text()).toContain('+5511999999000');
    await wrapper
      .findAll('[aria-pressed]')
      .find(button => button.text().includes('CONSENT_SCREEN.PENDING'))
      .trigger('click');
    expect(wrapper.find('article').text()).toContain('+5511999999001');
    wrapper.vm.filter = 'all';
    await wrapper.find('input[type="search"]').setValue('+55 (11) 99999-9002');
    expect(wrapper.findAll('article')).toHaveLength(1);
    expect(wrapper.find('article').text()).toContain('+5511999999002');
    expect(api.createConsent).not.toHaveBeenCalled();
  });

  it('paginates the list and returns to the first page when the search changes', async () => {
    api.consents.mockResolvedValue({
      data: Array.from({ length: 21 }, (_, index) => ({
        id: index + 1,
        phone_number: `+551199999${String(index).padStart(4, '0')}`,
        purpose: 'whatsapp_campaigns',
      })),
    });
    await wrapper.vm.load();
    expect(wrapper.findAll('article')).toHaveLength(20);
    await wrapper.find('nav button:last-child').trigger('click');
    expect(wrapper.findAll('article')).toHaveLength(1);
    await wrapper.find('input[type="search"]').setValue('0020');
    expect(wrapper.vm.page).toBe(1);
    expect(wrapper.findAll('article')).toHaveLength(1);
    expect(wrapper.find('nav').exists()).toBe(false);
  });

  it('keeps evidence and revocation inside collapsed details', async () => {
    api.consents.mockResolvedValue({
      data: [
        {
          id: 1,
          phone_number: '+5511999999000',
          purpose: 'whatsapp_campaigns',
          evidence: 'Original holder evidence',
        },
      ],
    });
    await wrapper.vm.load();
    const details = wrapper.find('article details');
    expect(details.attributes('open')).toBeUndefined();
    expect(details.text()).toContain('Original holder evidence');
    expect(details.find('button').text()).toBe(
      'JRC_CAMPAIGNS.GOVERNANCE.REVOKE'
    );
  });

  it('renders dates with the application pt_BR locale', () => {
    const date = '2026-10-20T12:00:00Z';
    expect(wrapper.vm.formatDate(date)).toBe(
      new Date(date).toLocaleString('pt-BR', {
        dateStyle: 'short',
        timeStyle: 'short',
      })
    );
  });

  it('offers a retry after a read failure instead of claiming the registry is empty', async () => {
    api.consents.mockRejectedValueOnce(new Error('Read failed'));
    await wrapper.vm.load();
    expect(wrapper.find('[role="alert"]').text()).toContain(
      'CONSENT_SCREEN.LOAD_FAILED'
    );
    const reads = api.consents.mock.calls.length;
    api.consents.mockResolvedValueOnce({ data: [] });
    await wrapper.find('[role="alert"] button').trigger('click');
    await flushPromises();
    expect(api.consents.mock.calls.length).toBe(reads + 1);
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
  });

  it('locks editor switching during an import and reloads the list after completion', async () => {
    await wrapper.vm.openEditor('import');
    const importer = wrapper.findComponent({ name: 'ConsentImportPanel' });
    importer.vm.$emit('busyChange', true);
    await wrapper.vm.$nextTick();
    expect(
      wrapper
        .findAll('[aria-controls]')
        .every(button => button.attributes('disabled') !== undefined)
    ).toBe(true);
    await wrapper.vm.reconfirm({ id: 9, phone_number: '+5511999999009' });
    expect(wrapper.vm.editor).toBe('import');
    const reads = api.consents.mock.calls.length;
    importer.vm.$emit('imported');
    await flushPromises();
    expect(api.consents.mock.calls.length).toBe(reads + 1);
    importer.vm.$emit('busyChange', false);
    await wrapper.vm.$nextTick();
    expect(
      wrapper
        .findAll('[aria-controls]')
        .every(button => button.attributes('disabled') === undefined)
    ).toBe(true);
  });
});
