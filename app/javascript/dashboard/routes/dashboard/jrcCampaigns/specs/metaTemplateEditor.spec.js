import { mount, flushPromises } from '@vue/test-utils';
import MetaTemplateEditor from '../components/MetaTemplateEditor.vue';
import api from 'dashboard/api/jrcCampaigns';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/jrcCampaigns', () => ({
  default: {
    templateMedia: vi.fn(),
    uploadMedia: vi.fn(),
    importMetaMedia: vi.fn(),
  },
}));
const template = {
  name: 'invitation',
  language: 'pt_BR',
  status: 'APPROVED',
  components: [
    {
      type: 'HEADER',
      format: 'IMAGE',
      example: { header_handle: ['https://example.test/example'] },
    },
  ],
};

describe('Meta template example media', () => {
  it('automatically imports the approved example without requiring an upload', async () => {
    api.templateMedia.mockResolvedValue({
      data: {
        id: 7,
        url: 'https://app.test/retained',
        file_name: 'example.png',
      },
    });
    const wrapper = mount(MetaTemplateEditor, {
      props: { inboxId: 3, template, modelValue: {} },
    });
    await flushPromises();
    expect(api.templateMedia).toHaveBeenCalledWith(3, 'invitation', 'pt_BR');
    expect(
      wrapper.emitted('update:modelValue')[0][0].processed_params.header
    ).toMatchObject({ media_asset_id: 7, media_type: 'image' });
    wrapper.unmount();
  });
  it('preserves a manually selected media and avoids repeated imports', async () => {
    const wrapper = mount(MetaTemplateEditor, {
      props: {
        inboxId: 3,
        template,
        modelValue: {
          processed_params: {
            header: { media_asset_id: 10, media_type: 'image' },
          },
        },
      },
    });
    await flushPromises();
    expect(api.templateMedia).not.toHaveBeenCalled();
    wrapper.unmount();
  });
  it('requests a manual upload when the example is expired', async () => {
    api.templateMedia.mockRejectedValue(new Error('expired'));
    const wrapper = mount(MetaTemplateEditor, {
      props: { inboxId: 3, template, modelValue: {} },
    });
    await flushPromises();
    expect(wrapper.find('[role="alert"]').text()).toContain(
      'EXAMPLE_UNAVAILABLE'
    );
    expect(wrapper.find('input[type="file"]').exists()).toBe(true);
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
    wrapper.unmount();
  });
});
