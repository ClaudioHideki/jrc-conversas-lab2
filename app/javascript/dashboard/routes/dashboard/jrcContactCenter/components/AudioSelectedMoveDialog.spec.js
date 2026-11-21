import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import locale from 'dashboard/i18n/locale/en/jrcContactCenter.json';
import API from 'dashboard/api/jrcContactCenter';
import AudioSelectedMoveDialog from './AudioSelectedMoveDialog.vue';

vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: {
    audioAsset: vi.fn(),
    audioUsages: vi.fn(),
    moveAudioAssets: vi.fn(),
  },
}));
vi.mock('dashboard/components-next/icon/Icon.vue', () => ({
  default: { template: '<span />' },
}));
vi.mock('dashboard/components-next/dialog/Dialog.vue', async () => {
  const { h, ref } = await import('vue');
  return {
    default: {
      props: {
        disableConfirmButton: Boolean,
        confirmButtonLabel: String,
        cancelButtonLabel: String,
      },
      emits: ['confirm', 'close'],
      setup(props, { expose, emit, slots }) {
        const visible = ref(false);
        expose({
          open: () => {
            visible.value = true;
          },
          close: () => {
            visible.value = false;
            emit('close');
          },
        });
        return () =>
          visible.value
            ? h('div', { role: 'dialog' }, [
                slots.default?.(),
                h(
                  'button',
                  {
                    'data-private-confirm': true,
                    disabled: props.disableConfirmButton,
                    onClick: () => emit('confirm'),
                  },
                  props.confirmButtonLabel
                ),
                h(
                  'button',
                  { 'data-private-close': true, onClick: () => emit('close') },
                  props.cancelButtonLabel
                ),
              ])
            : null;
      },
    },
  };
});
vi.mock('./AudioFolderPicker.vue', async () => {
  const { h, onMounted } = await import('vue');
  return {
    default: {
      props: {
        modelValue: String,
        accountId: [String, Number],
        unitId: String,
        disabled: Boolean,
      },
      emits: ['update:modelValue', 'loading'],
      setup(props, { emit }) {
        onMounted(() => emit('loading', false));
        return () =>
          h(
            'select',
            {
              'data-private-picker': true,
              'data-account': props.accountId,
              'data-unit': props.unitId,
              disabled: props.disabled,
              value: props.modelValue,
              onChange: event => emit('update:modelValue', event.target.value),
            },
            [
              h('option', { value: '' }, 'Pasta raiz'),
              h('option', { value: '20' }, 'SYNTHETIC pasta de destino'),
            ]
          );
      },
    },
  };
});
const row = () => ({
  assetId: '21',
  versionId: '22',
  revision: 'a'.repeat(64),
  sha256: 'b'.repeat(64),
  name: 'SYNTHETIC selected audio',
  number: 1,
});
const actual = () => ({
  id: '21',
  unit_id: '10',
  revision: 'a'.repeat(64),
  latest_version: { id: '22', sha256: 'b'.repeat(64) },
});
const fixture = (extra = {}) => {
  const messages = JSON.parse(JSON.stringify(locale));
  return mount(AudioSelectedMoveDialog, {
    props: {
      accountId: '1',
      unitId: '10',
      contextKey: 'SYNTHETIC profile',
      canManage: true,
      selection: [row()],
      ...extra,
    },
    global: {
      plugins: [
        createI18n({ legacy: false, locale: 'en', messages: { en: messages } }),
      ],
    },
  });
};
enableAutoUnmount(cleanup =>
  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  })
);
beforeEach(() => {
  vi.clearAllMocks();
  API.audioAsset.mockResolvedValue({
    data: { account_id: '1', item: actual() },
  });
  API.audioUsages.mockResolvedValue({
    data: {
      account_id: '1',
      unit_id: '10',
      audio_asset_id: '21',
      coverage: 'current_local_ivr_drafts_only',
      provider_configuration_verified: false,
      meta: { total: 2 },
    },
  });
  API.moveAudioAssets.mockResolvedValue({
    data: {
      account_id: '1',
      items: [{ ...actual(), folder_id: '20', revision: 'c'.repeat(64) }],
    },
  });
});

describe('selected audio move dialog (mocked Dialog/Picker, not actual CSS or persistence proof)', () => {
  it('reviews a native metadata record with no file without inventing a version or a checksum', async () => {
    API.audioAsset.mockResolvedValue({
      data: { account_id: '1', item: { ...actual(), latest_version: null } },
    });
    const wrapper = fixture({
      selection: [
        {
          ...row(),
          versionId: undefined,
          sha256: undefined,
          number: undefined,
        },
      ],
    });
    await wrapper.get('[data-open-audio-selected-move]').trigger('click');
    await flushPromises();
    expect(wrapper.get('[data-audio-selected-no-file]').text()).toContain(
      'Sem arquivo recebido'
    );
    expect(wrapper.text()).not.toContain('undefined');
    expect(wrapper.get('[data-private-confirm]').element.disabled).toBe(true);
    expect(API.moveAudioAssets).not.toHaveBeenCalled();
  });

  it('persists only the reviewed metadata identity and revision for a source with no native file', async () => {
    API.audioAsset.mockResolvedValue({
      data: { account_id: '1', item: { ...actual(), latest_version: null } },
    });
    API.moveAudioAssets.mockResolvedValue({
      data: {
        account_id: '1',
        items: [
          {
            ...actual(),
            latest_version: null,
            folder_id: null,
            revision: 'c'.repeat(64),
          },
        ],
      },
    });
    const wrapper = fixture({
      selection: [
        {
          ...row(),
          versionId: undefined,
          sha256: undefined,
          number: undefined,
        },
      ],
    });
    await wrapper.get('[data-open-audio-selected-move]').trigger('click');
    await flushPromises();
    await wrapper.get('[data-review-audio-selected-move]').setValue(true);
    await wrapper.get('[data-private-confirm]').trigger('click');
    await flushPromises();
    expect(API.moveAudioAssets).toHaveBeenCalledExactlyOnceWith('1', {
      unit_id: '10',
      folder_id: null,
      items: [{ audio_asset_id: '21', expected_revision: 'a'.repeat(64) }],
    });
    expect(wrapper.emitted('saved')).toHaveLength(1);
  });

  it('does not treat an incomplete source response as an explicitly absent native file', async () => {
    const incomplete = actual();
    delete incomplete.latest_version;
    API.audioAsset.mockResolvedValue({
      data: { account_id: '1', item: incomplete },
    });
    const wrapper = fixture({
      selection: [
        {
          ...row(),
          versionId: undefined,
          sha256: undefined,
          number: undefined,
        },
      ],
    });
    await wrapper.get('[data-open-audio-selected-move]').trigger('click');
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toContain(
      'Um áudio mudou desde a seleção'
    );
    expect(wrapper.get('[data-private-confirm]').element.disabled).toBe(true);
    expect(API.moveAudioAssets).not.toHaveBeenCalled();
  });

  it('rejects a move receipt that omits the explicit no-file state instead of claiming persistence', async () => {
    API.audioAsset.mockResolvedValue({
      data: { account_id: '1', item: { ...actual(), latest_version: null } },
    });
    const incomplete = {
      ...actual(),
      folder_id: null,
      revision: 'c'.repeat(64),
    };
    delete incomplete.latest_version;
    API.moveAudioAssets.mockResolvedValue({
      data: { account_id: '1', items: [incomplete] },
    });
    const wrapper = fixture({
      selection: [
        {
          ...row(),
          versionId: undefined,
          sha256: undefined,
          number: undefined,
        },
      ],
    });
    await wrapper.get('[data-open-audio-selected-move]').trigger('click');
    await flushPromises();
    await wrapper.get('[data-review-audio-selected-move]').setValue(true);
    await wrapper.get('[data-private-confirm]').trigger('click');
    await flushPromises();
    expect(wrapper.emitted('saved')).toBeUndefined();
    expect(wrapper.get('[role="alert"]').exists()).toBe(true);
    expect(wrapper.get('[data-private-confirm]').element.disabled).toBe(true);
  });

  it('keeps the action disabled without selection, configure capability or valid reviewed revision', async () => {
    const wrapper = fixture({ selection: [] });
    expect(
      wrapper.get('[data-open-audio-selected-move]').element.disabled
    ).toBe(true);
    await wrapper.setProps({ selection: [row()], canManage: false });
    expect(
      wrapper.get('[data-open-audio-selected-move]').element.disabled
    ).toBe(true);
    expect(API.audioAsset).not.toHaveBeenCalled();
  });

  it('shows Portuguese review, exact version and local dependency count before explicit confirmation', async () => {
    const wrapper = fixture();
    await wrapper.get('[data-open-audio-selected-move]').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('Mover selecionados');
    expect(wrapper.text()).toContain(
      'Identidades, arquivos, versões e vínculos são preservados'
    );
    expect(
      wrapper.get('[data-audio-selected-move-item="21"]').text()
    ).toContain('Áudio 21 · Versão 1');
    expect(wrapper.get('[data-private-confirm]').element.disabled).toBe(true);
    expect(wrapper.get('[data-private-confirm]').text()).toBe('Mover áudios');
    await wrapper.get('[data-private-picker]').setValue('20');
    await wrapper.get('[data-review-audio-selected-move]').setValue(true);
    await wrapper.get('[data-private-confirm]').trigger('click');
    await flushPromises();
    expect(API.moveAudioAssets).toHaveBeenCalledExactlyOnceWith('1', {
      unit_id: '10',
      folder_id: '20',
      items: [{ audio_asset_id: '21', expected_revision: 'a'.repeat(64) }],
    });
    expect(wrapper.emitted('saved')).toHaveLength(1);
  });

  it('preserves the reviewed destination after failure and requires a fresh review before another write', async () => {
    const wrapper = fixture();
    await wrapper.get('[data-open-audio-selected-move]').trigger('click');
    await flushPromises();
    await wrapper.get('[data-private-picker]').setValue('20');
    await wrapper.get('[data-review-audio-selected-move]').setValue(true);
    API.moveAudioAssets.mockRejectedValue({ response: { status: 409 } });
    await wrapper.get('[data-private-confirm]').trigger('click');
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toContain(
      'Um áudio mudou desde a seleção'
    );
    expect(wrapper.get('[data-private-picker]').element.value).toBe('20');
    expect(wrapper.get('[data-private-confirm]').element.disabled).toBe(true);
    expect(wrapper.emitted('saved')).toBeUndefined();
  });

  it('forgets private review on profile change and does not retain an active dialog', async () => {
    const wrapper = fixture();
    await wrapper.get('[data-open-audio-selected-move]').trigger('click');
    await flushPromises();
    await wrapper.setProps({
      contextKey: 'SYNTHETIC restricted profile',
      canManage: false,
    });
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
    expect(API.moveAudioAssets).not.toHaveBeenCalled();
  });
});
