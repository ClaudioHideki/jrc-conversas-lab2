import { flushPromises, mount } from '@vue/test-utils';
import ConsentImportPanel from '../components/ConsentImportPanel.vue';
import api from 'dashboard/api/jrcCampaigns';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/jrcCampaigns', () => ({
  default: {
    previewConsentImport: vi.fn(),
    importConsents: vi.fn(),
  },
}));

describe('Consent CSV import', () => {
  let wrapper;
  const csv =
    'phone_number,source,granted_at,evidence\n5511999999000,Form,2026-01-01T12:00:00-03:00,Recurring permission';
  const file = { size: csv.length, text: async () => csv };
  beforeEach(() => {
    vi.clearAllMocks();
    api.previewConsentImport.mockResolvedValue({
      data: {
        total: 1,
        ready: 1,
        existing: 0,
        errors: 0,
        rows: [{ line: 2, phone_number: '+5511999999000', status: 'ready' }],
      },
    });
    api.importConsents.mockResolvedValue({
      data: { imported: 1, existing: 0 },
    });
    wrapper = mount(ConsentImportPanel);
  });
  afterEach(() => wrapper.unmount());

  it('previews without importing and requires a fresh scope confirmation', async () => {
    await wrapper.vm.selectFile({ target: { files: [file] } });
    expect(api.previewConsentImport).toHaveBeenCalledExactlyOnceWith(csv);
    expect(wrapper.find('tbody').text()).toContain('+5511999999000');
    await wrapper.vm.importCsv();
    expect(api.importConsents).not.toHaveBeenCalled();
    expect(wrapper.find('input[type="checkbox"]').element.checked).toBe(false);
  });

  it('imports only after confirmation and refreshes the consent list without sending', async () => {
    await wrapper.vm.selectFile({ target: { files: [file] } });
    await wrapper.find('input[type="checkbox"]').setValue(true);
    await wrapper.vm.importCsv();
    await flushPromises();
    expect(api.importConsents).toHaveBeenCalledExactlyOnceWith(csv, true);
    expect(wrapper.emitted('imported')).toHaveLength(1);
    expect(wrapper.find('table').exists()).toBe(false);
    expect(wrapper.find('[role="status"]').text()).toBe(
      'JRC_CAMPAIGNS.CONSENT_IMPORT.RESULT'
    );
  });

  it('clears confirmation and prior preview when selecting another file', async () => {
    await wrapper.vm.selectFile({ target: { files: [file] } });
    await wrapper.find('input[type="checkbox"]').setValue(true);
    await wrapper.vm.selectFile({ target: { files: [file] } });
    expect(wrapper.find('input[type="checkbox"]').element.checked).toBe(false);
    await wrapper.vm.importCsv();
    expect(api.importConsents).not.toHaveBeenCalled();
  });

  it.each([
    { ready: 1, errors: 1 },
    { ready: 0, errors: 0 },
  ])(
    'disables import for invalid rows or an entirely existing file: %j',
    async data => {
      api.previewConsentImport.mockResolvedValueOnce({
        data: { ...data, rows: [] },
      });
      await wrapper.vm.selectFile({ target: { files: [file] } });
      wrapper.vm.confirmed = true;
      await wrapper.vm.importCsv();
      expect(api.importConsents).not.toHaveBeenCalled();
    }
  );

  it('rejects oversized files before reading or uploading', async () => {
    const text = vi.fn();
    await wrapper.vm.selectFile({
      target: { files: [{ size: 1024 * 1024 + 1, text }] },
    });
    expect(text).not.toHaveBeenCalled();
    expect(api.previewConsentImport).not.toHaveBeenCalled();
    expect(wrapper.find('[role="alert"]').text()).toBe(
      'JRC_CAMPAIGNS.CONSENT_IMPORT.SIZE_ERROR'
    );
  });

  it('shows server errors and clears the confirmation when a changed grant blocks import', async () => {
    await wrapper.vm.selectFile({ target: { files: [file] } });
    await wrapper.find('input[type="checkbox"]').setValue(true);
    api.importConsents.mockRejectedValue({
      response: { data: { errors: ['Grant revoked after preview'] } },
    });
    await wrapper.vm.importCsv();
    expect(wrapper.find('[role="alert"]').text()).toContain(
      'Grant revoked after preview'
    );
    expect(wrapper.find('input[type="checkbox"]').element.checked).toBe(false);
    expect(wrapper.emitted('imported')).toBeUndefined();
  });
});
