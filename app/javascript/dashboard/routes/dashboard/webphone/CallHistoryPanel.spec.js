import { flushPromises, mount } from '@vue/test-utils';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { createI18n } from 'vue-i18n';
import calls from 'dashboard/i18n/locale/pt_BR/calls.json';
import CallHistoryAPI from 'dashboard/api/callHistory';
import CallHistoryPanel from './CallHistoryPanel.vue';

vi.mock('dashboard/api/callHistory', () => ({
  default: { get: vi.fn(), recording: vi.fn() },
}));

vi.mock('dashboard/api/callQualityAnalyses', () => ({
  default: { analyze: vi.fn() },
}));

describe('CallHistoryPanel', () => {
  const mountConfig = {};
  beforeEach(() => {
    URL.createObjectURL = vi.fn(() => 'blob:synthetic');
    URL.revokeObjectURL = vi.fn();
    mountConfig.global = {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'pt_BR',
          messages: { pt_BR: calls },
        }),
      ],
    };
    vi.clearAllMocks();
    CallHistoryAPI.get.mockResolvedValue({
      data: {
        count: 2,
        extension: '1110',
        fetched_at: '2026-08-19T12:00:00Z',
        summary: { total: 2, answered: 1, unanswered: 1 },
        calls: [
          {
            id: '1',
            direction: 'outbound',
            status: 'answered',
            external_number: '11999999999',
            started_at: '2026-08-19T10:00:00Z',
          },
          {
            id: '2',
            direction: 'inbound',
            status: 'unanswered',
            external_number: '11888888888',
            started_at: '2026-08-19T11:00:00Z',
          },
        ],
      },
    });
  });

  it('renders real summary values and distinct call statuses', async () => {
    const wrapper = mount(CallHistoryPanel, mountConfig);
    await flushPromises();

    expect(CallHistoryAPI.get).toHaveBeenCalled();
    expect(wrapper.text()).toContain('Total de chamadas');
    expect(wrapper.text()).toContain('Atendidas');
    expect(wrapper.text()).toContain('Não atendidas');
    expect(wrapper.find('.bg-n-teal-3').text()).toContain('1');
    expect(wrapper.find('.bg-n-ruby-3').text()).toContain('1');
    expect(wrapper.text()).toContain('Atendida');
    expect(wrapper.text()).toContain('Nao atendida');
    wrapper.unmount();
  });

  it('renders the newest call first', async () => {
    const wrapper = mount(CallHistoryPanel, mountConfig);
    await flushPromises();

    expect(wrapper.findAll('article')[0].text()).toContain('11888888888');
    wrapper.unmount();
  });

  it('shows loading until the authorized response arrives', async () => {
    let resolve;
    CallHistoryAPI.get.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const wrapper = mount(CallHistoryPanel, mountConfig);
    await wrapper.vm.$nextTick();
    expect(wrapper.text()).toContain('Buscando histórico');
    resolve({ data: { calls: [], count: 0 } });
    await flushPromises();
    expect(wrapper.text()).toContain('Nenhuma chamada');
    wrapper.unmount();
  });

  it('resets pagination when applying filters', async () => {
    CallHistoryAPI.get.mockResolvedValue({
      data: { calls: [], count: 250, provider: 'pabx_v1' },
    });
    const wrapper = mount(CallHistoryPanel, mountConfig);
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(button => button.text() === calls.SOFTPHONE.PABX.NEXT)
      .trigger('click');
    await flushPromises();
    expect(CallHistoryAPI.get.mock.lastCall[0].page).toBe(2);
    await wrapper.find('select').setValue('outbound');
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Aplicar filtros')
      .trigger('click');
    await flushPromises();
    expect(CallHistoryAPI.get.mock.lastCall[0]).toMatchObject({
      page: 1,
      direction: 'outbound',
      time_zone: 'America/Sao_Paulo',
    });
    wrapper.unmount();
  });

  it('clears cached calls and totals after a blocked request', async () => {
    const wrapper = mount(CallHistoryPanel, mountConfig);
    await flushPromises();
    expect(wrapper.findAll('article')).toHaveLength(2);
    CallHistoryAPI.get.mockRejectedValueOnce({
      response: { data: { message: 'Tenant incompatível' } },
    });
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Aplicar filtros')
      .trigger('click');
    await flushPromises();
    expect(wrapper.findAll('article')).toHaveLength(0);
    expect(wrapper.text()).toContain('Tenant incompatível');
    expect(wrapper.vm.total).toBe(0);
    wrapper.unmount();
  });

  it('uses the displayed Sao Paulo day rather than the UTC day for filters', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-10-15T01:00:00Z'));
    const wrapper = mount(CallHistoryPanel, mountConfig);
    await flushPromises();
    expect(CallHistoryAPI.get.mock.lastCall[0]).toMatchObject({
      start_date: '2026-10-08',
      end_date: '2026-10-14',
    });
    wrapper.unmount();
    vi.useRealTimers();
  });

  const recordingData = (id = 1, state = 'requestable') => ({
    id,
    unique_id: `synthetic-${id}`,
    provider: 'pabx_v1',
    has_recording: true,
    recording_state: state,
    started_at: '2026-10-15T10:00:00Z',
  });
  const showRecordings = rows =>
    CallHistoryAPI.get.mockResolvedValue({
      data: { calls: rows, count: rows.length, provider: 'pabx_v1' },
    });

  it('does not download recordings automatically and shows pending or absent metadata', async () => {
    showRecordings([
      recordingData(1, 'mapping_pending'),
      { ...recordingData(2), has_recording: false, recording_state: 'none' },
    ]);
    const wrapper = mount(CallHistoryPanel, mountConfig);
    await flushPromises();
    expect(CallHistoryAPI.recording).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain(calls.SOFTPHONE.PABX.RECORDING_PENDING);
    expect(wrapper.text()).toContain(calls.SOFTPHONE.PABX.RECORDING_NONE);
    wrapper.unmount();
  });

  it('loads an authorized recording once and revokes its private object URL when leaving', async () => {
    showRecordings([recordingData()]);
    CallHistoryAPI.recording.mockResolvedValue({
      data: new Blob(['synthetic wav'], { type: 'audio/wav' }),
    });
    const wrapper = mount(CallHistoryPanel, mountConfig);
    await flushPromises();
    const button = wrapper
      .findAll('button')
      .find(item => item.text() === calls.SOFTPHONE.PABX.LOAD_RECORDING);
    await button.trigger('click');
    await flushPromises();
    expect(CallHistoryAPI.recording).toHaveBeenCalledOnce();
    expect(wrapper.find('audio').attributes('src')).toBe('blob:synthetic');
    wrapper.unmount();
    expect(URL.revokeObjectURL).toHaveBeenCalledWith('blob:synthetic');
  });

  it('keeps the call history visible when a recording is expired', async () => {
    showRecordings([recordingData()]);
    CallHistoryAPI.recording.mockRejectedValue({ response: { status: 410 } });
    const wrapper = mount(CallHistoryPanel, mountConfig);
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(item => item.text() === calls.SOFTPHONE.PABX.LOAD_RECORDING)
      .trigger('click');
    await flushPromises();
    expect(wrapper.findAll('article')).toHaveLength(1);
    expect(wrapper.find('[role="alert"]').text()).toBe(
      calls.SOFTPHONE.PABX.RECORDING_EXPIRED
    );
    wrapper.unmount();
  });

  it('revokes the old clip after refreshing the authorized call list', async () => {
    showRecordings([recordingData()]);
    CallHistoryAPI.recording.mockResolvedValue({
      data: new Blob(['synthetic wav'], { type: 'audio/wav' }),
    });
    const wrapper = mount(CallHistoryPanel, mountConfig);
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(item => item.text() === calls.SOFTPHONE.PABX.LOAD_RECORDING)
      .trigger('click');
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(item => item.text() === 'Aplicar filtros')
      .trigger('click');
    await flushPromises();
    expect(URL.revokeObjectURL).toHaveBeenCalledWith('blob:synthetic');
    expect(wrapper.find('audio').exists()).toBe(false);
    wrapper.unmount();
  });

  it('aborts and ignores a recording response that arrives after unmount', async () => {
    showRecordings([recordingData()]);
    let resolve;
    CallHistoryAPI.recording.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const wrapper = mount(CallHistoryPanel, mountConfig);
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(item => item.text() === calls.SOFTPHONE.PABX.LOAD_RECORDING)
      .trigger('click');
    const signal = CallHistoryAPI.recording.mock.lastCall[1].signal;
    wrapper.unmount();
    expect(signal.aborted).toBe(true);
    resolve({ data: new Blob(['synthetic wav'], { type: 'audio/wav' }) });
    await flushPromises();
    expect(URL.createObjectURL).not.toHaveBeenCalled();
  });

  it('keeps only one audio clip in memory when selecting another call', async () => {
    showRecordings([recordingData(1), recordingData(2)]);
    URL.createObjectURL
      .mockReturnValueOnce('blob:first')
      .mockReturnValueOnce('blob:second');
    CallHistoryAPI.recording.mockResolvedValue({
      data: new Blob(['synthetic wav'], { type: 'audio/wav' }),
    });
    const wrapper = mount(CallHistoryPanel, mountConfig);
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(item => item.text() === calls.SOFTPHONE.PABX.LOAD_RECORDING)
      .trigger('click');
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(item => item.text() === calls.SOFTPHONE.PABX.LOAD_RECORDING)
      .trigger('click');
    await flushPromises();
    expect(URL.revokeObjectURL).toHaveBeenCalledWith('blob:first');
    expect(wrapper.findAll('audio')).toHaveLength(1);
    expect(wrapper.find('audio').attributes('src')).toBe('blob:second');
    wrapper.unmount();
  });
});
