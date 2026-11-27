import { afterEach, describe, expect, it, vi } from 'vitest';
import { flushPromises, mount, enableAutoUnmount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import RecordingTranscript from './RecordingTranscript.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { recordingTranscript: vi.fn() },
}));
enableAutoUnmount(afterEach);
afterEach(() => vi.clearAllMocks());
const payload = (overrides = {}) => ({
  account_id: '1',
  recording_id: '15',
  call_session_id: '27',
  call_id: 'SYNTHETIC-call',
  source_sha256: 'a'.repeat(64),
  text: 'SYNTHETIC original\nCliente: Entrega pendente',
  segments: [],
  temporal_alignment: 'not_supplied_by_native_source',
  ...overrides,
});
const create = () =>
  mount(RecordingTranscript, {
    props: { accountId: 1, recordingId: 15, callId: 'SYNTHETIC-call' },
  });

describe('authorized original transcript without invented timing', () => {
  it('shows immutable original text and the explicit timing limitation without an audio or inference request', async () => {
    API.recordingTranscript.mockResolvedValue({ data: payload() });
    const wrapper = create();
    await flushPromises();
    expect(API.recordingTranscript).toHaveBeenCalledTimes(1);
    expect(API.recordingTranscript).toHaveBeenCalledWith('1', '15');
    expect(wrapper.get('[data-transcript-text]').text()).toContain(
      'Entrega pendente'
    );
    expect(wrapper.get('[data-transcript-timing-limit]').text()).toContain(
      'NO_TIMESTAMPS'
    );
    expect(wrapper.get('[data-transcript-source]').text()).toContain(
      'a'.repeat(64)
    );
    expect(wrapper.find('audio').exists()).toBe(false);
    expect(wrapper.emitted('playback')).toBeUndefined();
  });

  it('searches actual text locally, restores the complete original and never labels matches as measured segments', async () => {
    API.recordingTranscript.mockResolvedValue({ data: payload() });
    const wrapper = create();
    await flushPromises();
    await wrapper.get('[data-transcript-search]').setValue('ENTREGA');
    expect(wrapper.findAll('[data-transcript-block]')).toHaveLength(1);
    expect(wrapper.get('[data-transcript-block]').text()).toBe(
      'Cliente: Entrega pendente'
    );
    await wrapper.get('[data-transcript-search]').setValue('absent');
    expect(wrapper.find('[data-transcript-no-matches]').exists()).toBe(true);
    await wrapper.get('[data-transcript-search]').setValue('');
    expect(wrapper.get('[data-transcript-text]').text()).toContain(
      'SYNTHETIC original'
    );
    expect(API.recordingTranscript).toHaveBeenCalledTimes(1);
  });

  it('renders markup as literal text and never executes source HTML', async () => {
    API.recordingTranscript.mockResolvedValue({
      data: payload({ text: '<img src=x onerror=alert(1)>SYNTHETIC' }),
    });
    const wrapper = create();
    await flushPromises();
    expect(wrapper.find('img').exists()).toBe(false);
    expect(wrapper.get('[data-transcript-text]').text()).toContain(
      '<img src=x onerror=alert(1)>'
    );
  });

  it('reports absent original text without creating dialogue, timestamps or sentiment values', async () => {
    API.recordingTranscript.mockResolvedValue({
      data: payload({ text: null }),
    });
    const wrapper = create();
    await flushPromises();
    expect(wrapper.find('[data-transcript-empty]').exists()).toBe(true);
    expect(wrapper.find('[data-transcript-search]').exists()).toBe(false);
    expect(wrapper.find('[data-transcript-text]').exists()).toBe(false);
  });

  it('ignores a late response after a rapid account and conversation change', async () => {
    let complete;
    API.recordingTranscript.mockReturnValueOnce(
      new Promise(resolve => {
        complete = resolve;
      })
    );
    const wrapper = create();
    API.recordingTranscript.mockResolvedValueOnce({
      data: payload({
        account_id: '2',
        recording_id: '22',
        call_id: 'SYNTHETIC-other',
        text: 'AUTHORIZED second',
      }),
    });
    await wrapper.setProps({
      accountId: 2,
      recordingId: 22,
      callId: 'SYNTHETIC-other',
    });
    await flushPromises();
    complete({ data: payload({ text: 'STALE first private text' }) });
    await flushPromises();
    expect(wrapper.text()).toContain('AUTHORIZED second');
    expect(wrapper.text()).not.toContain('STALE first private text');
  });

  it.each([
    { account_id: '2' },
    { recording_id: '99' },
    { call_id: 'foreign' },
  ])(
    'rejects a mismatched native identity despite successful HTTP: %j',
    async mismatch => {
      API.recordingTranscript.mockResolvedValueOnce({
        data: payload({ ...mismatch, text: 'FORBIDDEN text' }),
      });
      const wrapper = create();
      await flushPromises();
      expect(wrapper.get('[role=alert]').text()).toContain('ERROR');
      expect(wrapper.text()).not.toContain('FORBIDDEN text');
    }
  );

  it('clears private text on denied reload and permits recovery only through an explicit retry', async () => {
    API.recordingTranscript.mockRejectedValueOnce({
      response: { status: 401 },
    });
    const wrapper = create();
    await flushPromises();
    expect(wrapper.get('[role=alert]').text()).toContain('DENIED');
    expect(wrapper.find('[data-transcript-text]').exists()).toBe(false);
    API.recordingTranscript.mockResolvedValueOnce({ data: payload() });
    await wrapper.get('[data-transcript-retry]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[role=alert]').exists()).toBe(false);
    expect(wrapper.get('[data-transcript-text]').text()).toContain(
      'SYNTHETIC original'
    );
  });

  it('keeps source failure explicit, with no automatic retry, media command or partial text', async () => {
    API.recordingTranscript.mockRejectedValueOnce({
      response: { status: 503 },
    });
    const wrapper = create();
    await flushPromises();
    expect(wrapper.get('[role=alert]').text()).toContain('UNAVAILABLE');
    expect(API.recordingTranscript).toHaveBeenCalledTimes(1);
    expect(wrapper.find('[data-transcript-text]').exists()).toBe(false);
    expect(wrapper.emitted()).not.toHaveProperty('playback');
  });
});
