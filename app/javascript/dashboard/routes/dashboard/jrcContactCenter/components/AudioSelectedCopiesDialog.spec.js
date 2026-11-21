import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import locale from 'dashboard/i18n/locale/en/jrcContactCenter.json';
import API from 'dashboard/api/jrcContactCenter';
import AudioSelectedCopiesDialog from './AudioSelectedCopiesDialog.vue';

vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { audioAsset: vi.fn(), duplicateAudioAsset: vi.fn() },
}));
vi.mock('dashboard/components-next/icon/Icon.vue', () => ({
  default: { template: '<span />' },
}));
vi.mock('dashboard/components-next/button/Button.vue', () => ({
  default: {
    props: { label: String, disabled: Boolean, isLoading: Boolean },
    emits: ['click'],
    template:
      '<button type="button" :disabled="disabled || isLoading" @click="$emit(\'click\')">{{ label }}</button>',
  },
}));
vi.mock('dashboard/components-next/dialog/Dialog.vue', async () => {
  const { h, ref } = await import('vue');
  return {
    default: {
      props: {
        disableConfirmButton: Boolean,
        confirmButtonLabel: String,
        cancelButtonLabel: String,
        showConfirmButton: { type: Boolean, default: true },
      },
      emits: ['confirm', 'close'],
      setup(props, { emit, expose, slots }) {
        const visible = ref(false);
        const close = () => {
          visible.value = false;
          emit('close');
        };
        expose({
          open: () => {
            visible.value = true;
          },
          close,
        });
        return () =>
          visible.value
            ? h('div', { role: 'dialog' }, [
                slots.default?.(),
                slots.footer
                  ? slots.footer()
                  : [
                      props.showConfirmButton
                        ? h(
                            'button',
                            {
                              'data-audio-selected-copies-confirm': true,
                              disabled: props.disableConfirmButton,
                              onClick: () => emit('confirm'),
                            },
                            props.confirmButtonLabel
                          )
                        : null,
                      h(
                        'button',
                        {
                          'data-audio-selected-copies-close': true,
                          onClick: close,
                        },
                        props.cancelButtonLabel
                      ),
                    ],
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
        modelValue: [String, Number],
        accountId: [String, Number],
        unitId: String,
        currentName: String,
        disabled: Boolean,
      },
      emits: ['update:modelValue', 'loading', 'denied'],
      setup(props, { emit }) {
        onMounted(() => emit('loading', false));
        return () =>
          h(
            'div',
            {
              'data-private-copy-picker': true,
              'data-unit': props.unitId,
              'data-account': props.accountId,
            },
            [
              h(
                'select',
                {
                  'data-private-copy-folder': true,
                  disabled: props.disabled,
                  value: props.modelValue,
                  onChange: event =>
                    emit('update:modelValue', event.target.value),
                },
                [
                  h('option', { value: '' }, 'Pasta raiz'),
                  h('option', { value: '20' }, 'SYNTHETIC destination'),
                ]
              ),
              h(
                'button',
                {
                  'data-private-copy-folder-denied': true,
                  onClick: () => emit('denied'),
                },
                'SYNTHETIC scope denial'
              ),
            ]
          );
      },
    },
  };
});
const selection = () =>
  [0, 1].map(index => ({
    assetId: String(21 + index),
    versionId: String(121 + index),
    inspectionId: String(221 + index),
    name: `SYNTHETIC source ${index}`,
    revision: 'a'.repeat(64),
    sha256: String(index + 1).repeat(64),
    number: 1,
    byteSize: 60,
  }));
const actual = id => {
  const row = selection().find(item => item.assetId === id);
  return {
    id,
    unit_id: '10',
    name: row.name,
    revision: row.revision,
    description: '',
    purpose: '',
    latest_version: {
      id: row.versionId,
      number: 1,
      sha256: row.sha256,
      byte_size: 60,
      source_kind: 'user_upload',
      technical_verification: { id: row.inspectionId, ready: true },
    },
  };
};
const accepted = id => ({
  data: {
    account_id: '1',
    item: {
      id: String(Number(id) + 500),
      unit_id: '10',
      revision: 'b'.repeat(64),
    },
    received_version: {
      id: String(Number(id) + 600),
      audio_asset_id: String(Number(id) + 500),
      unit_id: '10',
      number: 1,
      source_kind: 'user_upload',
      sha256: actual(id).latest_version.sha256,
      byte_size: 60,
    },
  },
});
const fixture = (props = {}) => {
  const messages = structuredClone(locale);

  return mount(AudioSelectedCopiesDialog, {
    props: {
      accountId: '1',
      unitId: '10',
      contextKey: 'SYNTHETIC profile',
      canManage: true,
      admitted: true,
      selection: selection(),
      ...props,
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
  API.audioAsset.mockImplementation(async (_account, id) => ({
    data: { account_id: '1', item: actual(id) },
  }));
  API.duplicateAudioAsset.mockImplementation(async (_account, id) =>
    accepted(id)
  );
});

describe('selected audio copy popup (mocked Dialog/Picker, not native persistence or CSS)', () => {
  it('disables the actual footer dismissal while a native copy is unconfirmed instead of relying only on Dialog dismissible', async () => {
    let resolve;
    API.duplicateAudioAsset.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const wrapper = fixture();
    await wrapper.get('[data-open-audio-selected-copies]').trigger('click');
    await flushPromises();
    await wrapper.get('[data-review-audio-selected-copies]').setValue(true);
    await wrapper.get('[data-audio-selected-copies-confirm]').trigger('click');
    await flushPromises();
    const close = wrapper.get('[data-audio-selected-copies-close]');
    expect(close.element.disabled).toBe(true);
    expect(
      wrapper.get('[data-audio-selected-copies-confirm]').element.disabled
    ).toBe(true);
    await close.trigger('click');
    expect(wrapper.find('[role="dialog"]').exists()).toBe(true);
    expect(wrapper.emitted('settled')).toBeUndefined();
    resolve(accepted('21'));
    await flushPromises();
    expect(close.element.disabled).toBe(false);
    await close.trigger('click');
    await flushPromises();
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
    expect(wrapper.emitted('settled')[0][0].confirmed).toHaveLength(2);
  });
  it('keeps copy unavailable without the existing byte-admitted selection or configuration permission', async () => {
    const wrapper = fixture({ admitted: false });
    expect(
      wrapper.get('[data-open-audio-selected-copies]').element.disabled
    ).toBe(true);
    await wrapper.setProps({ admitted: true, canManage: false });
    expect(
      wrapper.get('[data-open-audio-selected-copies]').element.disabled
    ).toBe(true);
    expect(API.audioAsset).not.toHaveBeenCalled();
  });

  it('shows Portuguese scope, exact sources and reviewed names before serial native copy requests', async () => {
    const wrapper = fixture();
    await wrapper.get('[data-open-audio-selected-copies]').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('Cria novos cadastros na mesma unidade');
    expect(wrapper.findAll('[data-audio-selected-copy-item]')).toHaveLength(2);
    expect(
      wrapper.get('[data-private-copy-picker]').attributes('data-unit')
    ).toBe('10');
    expect(
      wrapper.get('[data-audio-selected-copies-confirm]').element.disabled
    ).toBe(true);
    const input = wrapper.get('[data-audio-selected-copy-name="21"]');
    expect(wrapper.get(`label[for="${input.attributes('id')}"]`).text()).toBe(
      'Nome da nova cópia'
    );
    await input.setValue('SYNTHETIC reviewed copy');
    await wrapper.get('[data-private-copy-folder]').setValue('20');
    await wrapper.get('[data-review-audio-selected-copies]').setValue(true);
    await wrapper.get('[data-audio-selected-copies-confirm]').trigger('click');
    await flushPromises();
    expect(API.duplicateAudioAsset.mock.calls.map(row => row[1])).toEqual([
      '21',
      '22',
    ]);
    expect(API.duplicateAudioAsset.mock.calls[0][2].asset).toEqual({
      name: 'SYNTHETIC reviewed copy',
      description: '',
      purpose: '',
      folder_id: '20',
    });
    expect(
      wrapper
        .get('[data-audio-selected-copies-counts]')
        .attributes('data-confirmed')
    ).toBe('2');
    expect(
      wrapper.get('[data-audio-selected-copies-complete]').text()
    ).toContain('Todas as cópias foram confirmadas');
    expect(wrapper.find('[data-audio-selected-copies-confirm]').exists()).toBe(
      false
    );
    expect(wrapper.emitted('settled')).toBeUndefined();
    await wrapper.get('[data-audio-selected-copies-close]').trigger('click');
    await flushPromises();
    expect(wrapper.emitted('settled')).toHaveLength(1);
    expect(wrapper.emitted('settled')[0][0].confirmed).toHaveLength(2);
  });

  it('shows a partial uncertain result and retries only the unconfirmed request with its original identity', async () => {
    API.duplicateAudioAsset
      .mockResolvedValueOnce(accepted('21'))
      .mockRejectedValueOnce(new Error('SYNTHETIC lost reply'));
    const wrapper = fixture();
    await wrapper.get('[data-open-audio-selected-copies]').trigger('click');
    await flushPromises();
    await wrapper.get('[data-review-audio-selected-copies]').setValue(true);
    await wrapper.get('[data-audio-selected-copies-confirm]').trigger('click');
    await flushPromises();
    expect(
      wrapper
        .get('[data-audio-selected-copies-counts]')
        .attributes('data-confirmed')
    ).toBe('1');
    expect(
      wrapper
        .get('[data-audio-selected-copies-counts]')
        .attributes('data-uncertain')
    ).toBe('1');
    expect(
      wrapper.get('[data-audio-selected-copy-name="21"]').element.disabled
    ).toBe(true);
    expect(
      wrapper.get('[data-audio-selected-copy-name="22"]').element.disabled
    ).toBe(true);
    expect(wrapper.get('[data-private-copy-folder]').element.disabled).toBe(
      true
    );
    expect(wrapper.get('[data-audio-selected-copies-confirm]').text()).toBe(
      'Retentar pendentes'
    );
    expect(
      wrapper.get('[data-audio-selected-copies-confirm]').element.disabled
    ).toBe(true);
    const previous = API.duplicateAudioAsset.mock.calls[1][2];
    await wrapper.get('[data-review-audio-selected-copies]').setValue(true);
    await wrapper.get('[data-audio-selected-copies-confirm]').trigger('click');
    await flushPromises();
    expect(API.duplicateAudioAsset.mock.calls.map(row => row[1])).toEqual([
      '21',
      '22',
      '22',
    ]);
    expect(API.duplicateAudioAsset.mock.calls[2][2]).toBe(previous);
    expect(
      wrapper
        .get('[data-audio-selected-copies-counts]')
        .attributes('data-confirmed')
    ).toBe('2');
  });

  it('clears source names and closes the popup after native folder access is denied', async () => {
    const wrapper = fixture();
    await wrapper.get('[data-open-audio-selected-copies]').trigger('click');
    await flushPromises();
    await wrapper.get('[data-private-copy-folder-denied]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
    expect(wrapper.emitted('denied')).toHaveLength(1);
    expect(wrapper.emitted('settled')).toBeUndefined();
    expect(API.duplicateAudioAsset).not.toHaveBeenCalled();
  });

  it('does not retain old private source data after a profile or account/unit context change', async () => {
    const wrapper = fixture();
    await wrapper.get('[data-open-audio-selected-copies]').trigger('click');
    await flushPromises();
    await wrapper.setProps({
      contextKey: 'SYNTHETIC restricted profile',
      canManage: false,
    });
    await flushPromises();
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
    expect(wrapper.text()).not.toContain('SYNTHETIC source');
    expect(wrapper.emitted('settled')).toBeUndefined();
  });
});
