import { mount, flushPromises } from '@vue/test-utils';
import MigrationCenter from '../MigrationCenter.vue';
import { createJrcMigrationsApi } from 'dashboard/api/jrcMigrations';

vi.mock('dashboard/api/jrcMigrations', () => ({
  createJrcMigrationsApi: vi.fn(),
}));
let wrapper;
afterEach(() => wrapper?.unmount());

const catalog = {
  contacts: ['legacy_id', 'name', 'email', 'created_at', 'updated_at'],
};
const item = {
  id: 1,
  legacy_id: 'person-1',
  decision: 'create',
  status: 'previewed',
  normalized_data: { name: 'Fixture' },
};
const staged = {
  id: 8,
  source: 'fixture',
  domain: 'contacts',
  status: 'staged',
  items: [item],
};
const apiFor = () => ({
  list: vi.fn().mockResolvedValue({ data: [], catalog, next_cursor: null }),
  show: vi.fn().mockResolvedValue(staged),
  create: vi.fn().mockResolvedValue(staged),
  preview: vi.fn().mockResolvedValue({ ...staged, status: 'previewed' }),
  execute: vi.fn().mockResolvedValue({ ...staged, status: 'executed' }),
  reconciliation: vi
    .fn()
    .mockResolvedValue({ total: 1, matched: 1, divergent: 0, blocked: 0 }),
  accept: vi.fn().mockResolvedValue({ ...staged, status: 'accepted' }),
});

it('requires staging and preview before a separate explicit execution', async () => {
  const api = apiFor();
  createJrcMigrationsApi.mockReturnValue(api);
  wrapper = mount(MigrationCenter, { props: { accountId: 1 } });
  await flushPromises();
  await wrapper.get('[data-testid="migration-source"]').setValue('fixture');
  const input = wrapper.get('input[type="file"]');
  Object.defineProperty(input.element, 'files', {
    value: [
      {
        name: 'fixture.json',
        size: 100,
        text: async () =>
          JSON.stringify([{ legacy_id: 'person-1', name: 'Fixture' }]),
      },
    ],
  });
  await input.trigger('change');
  await flushPromises();
  await wrapper.get('[data-testid="migration-stage"]').trigger('click');
  await flushPromises();
  expect(api.execute).not.toHaveBeenCalled();
  expect(wrapper.find('[data-testid="migration-execute"]').exists()).toBe(
    false
  );
  await wrapper.get('[data-testid="migration-preview"]').trigger('click');
  await flushPromises();
  expect(wrapper.text()).toContain('person-1');
  expect(api.execute).not.toHaveBeenCalled();
  await wrapper.get('[data-testid="migration-execute"]').trigger('click');
  await flushPromises();
  expect(api.execute).toHaveBeenCalledWith(8, expect.any(AbortSignal));
});

it('clears a previous account response after switching account', async () => {
  let finish;
  const first = apiFor();
  first.list.mockReturnValue(
    new Promise(resolve => {
      finish = resolve;
    })
  );
  const second = apiFor();
  createJrcMigrationsApi.mockReturnValueOnce(first).mockReturnValue(second);
  wrapper = mount(MigrationCenter, { props: { accountId: 1 } });
  await wrapper.setProps({ accountId: 2 });
  await flushPromises();
  finish({ data: [{ ...staged, source: 'FOREIGN-DATA' }], catalog });
  await flushPromises();
  expect(wrapper.text()).not.toContain('FOREIGN-DATA');
});

it('clears visible batch data when permission is revoked', async () => {
  const api = apiFor();
  api.list.mockResolvedValue({ data: [staged], catalog });
  api.preview.mockRejectedValue({ response: { status: 403 } });
  createJrcMigrationsApi.mockReturnValue(api);
  wrapper = mount(MigrationCenter, { props: { accountId: 1 } });
  await flushPromises();
  await wrapper.get('[data-testid="migration-batch-8"]').trigger('click');
  await flushPromises();
  await wrapper.get('[data-testid="migration-preview"]').trigger('click');
  await flushPromises();
  expect(wrapper.find('[data-testid="migration-preview"]').exists()).toBe(
    false
  );
  expect(wrapper.text()).not.toContain('person-1');
});

it('loads older immutable batch operations through the returned cursor', async () => {
  const api = apiFor();
  api.list.mockResolvedValue({ data: [staged], catalog });
  api.show.mockResolvedValue({
    ...staged,
    events: [
      {
        id: 4,
        action: 'EXECUTED',
        user_id: 1,
        occurred_at: '2026-11-02T12:00:00Z',
        metadata: {},
      },
    ],
    next_event_cursor: 4,
  });
  api.events = vi.fn().mockResolvedValue({
    data: [
      {
        id: 1,
        action: 'STAGED',
        user_id: 2,
        occurred_at: '2026-11-01T12:00:00Z',
        metadata: { source_digest: 'earlier-source' },
      },
    ],
    next_cursor: null,
  });
  createJrcMigrationsApi.mockReturnValue(api);
  wrapper = mount(MigrationCenter, { props: { accountId: 1 } });
  await flushPromises();
  await wrapper.get('[data-testid="migration-batch-8"]').trigger('click');
  await flushPromises();
  const more = wrapper
    .findAll('button')
    .find(button => button.text().includes('Load earlier operations'));
  await more.trigger('click');
  await flushPromises();
  expect(api.events).toHaveBeenCalledWith(8, 4, expect.any(AbortSignal));
  expect(wrapper.text()).toContain('earlier-source');
  expect(wrapper.findAll('li')).toHaveLength(2);
});

it('scans an imported file only after an explicit operator action and shows the returned verdict', async () => {
  const api = apiFor();
  const imported = {
    ...staged,
    domain: 'project_attachments',
    status: 'executed',
    items: [
      {
        ...item,
        status: 'applied',
        media: {
          status: 'attached',
          scan_state: 'unavailable',
          scannable: true,
          recoverable: false,
        },
      },
    ],
  };
  api.list.mockResolvedValue({ data: [imported], catalog });
  api.show.mockResolvedValue(imported);
  api.scanMedia = vi.fn().mockResolvedValue({
    ...imported,
    items: [
      {
        ...imported.items[0],
        media: { ...imported.items[0].media, scan_state: 'clean' },
      },
    ],
  });
  createJrcMigrationsApi.mockReturnValue(api);
  wrapper = mount(MigrationCenter, { props: { accountId: 1 } });
  await flushPromises();
  await wrapper.get('[data-testid="migration-batch-8"]').trigger('click');
  await flushPromises();
  expect(api.scanMedia).not.toHaveBeenCalled();
  await wrapper.get('[data-testid="migration-scan-1"]').trigger('click');
  await flushPromises();
  expect(api.scanMedia).toHaveBeenCalledWith(8, 1, expect.any(AbortSignal));
  expect(wrapper.get('[data-testid="migration-media-1"]').text()).toContain(
    'Verified clean'
  );
});

it('offers retry for an orphaned owned upload and removes that action after cleanup is confirmed', async () => {
  const api = apiFor();
  const interrupted = {
    ...staged,
    domain: 'project_attachments',
    status: 'executed',
    items: [
      {
        ...item,
        status: 'failed',
        media: {
          status: 'cleanup_required',
          scan_state: 'unavailable',
          scannable: false,
          recoverable: true,
        },
      },
    ],
  };
  api.list.mockResolvedValue({ data: [interrupted], catalog });
  api.show.mockResolvedValue(interrupted);
  api.recoverMedia = vi.fn().mockResolvedValue({
    ...interrupted,
    items: [
      {
        ...interrupted.items[0],
        media: {
          ...interrupted.items[0].media,
          status: 'cleaned',
          recoverable: false,
        },
      },
    ],
  });
  createJrcMigrationsApi.mockReturnValue(api);
  wrapper = mount(MigrationCenter, { props: { accountId: 1 } });
  await flushPromises();
  await wrapper.get('[data-testid="migration-batch-8"]').trigger('click');
  await flushPromises();
  expect(wrapper.find('[data-testid="migration-scan-1"]').exists()).toBe(false);
  await wrapper
    .get('[data-testid="migration-media-recovery-1"]')
    .trigger('click');
  await flushPromises();
  expect(api.recoverMedia).toHaveBeenCalledWith(8, 1, expect.any(AbortSignal));
  expect(
    wrapper.find('[data-testid="migration-media-recovery-1"]').exists()
  ).toBe(false);
  expect(wrapper.get('[data-testid="migration-media-1"]').text()).toContain(
    'Cleanup confirmed'
  );
});

it.each([
  ['reserved', 'File awaiting destination verification'],
  ['verifying', 'Checking file destination'],
  ['verification_required', 'Validate this file preview again'],
])(
  'explains %s without offering scanning or deletion before ownership is verified',
  async (status, label) => {
    const api = apiFor();
    const batch = {
      ...staged,
      domain: 'project_attachments',
      items: [
        {
          ...item,
          media: {
            status,
            scannable: false,
            recoverable: false,
            scan_state: 'unavailable',
          },
        },
      ],
    };
    api.list.mockResolvedValue({ data: [batch], catalog });
    api.show.mockResolvedValue(batch);
    createJrcMigrationsApi.mockReturnValue(api);
    wrapper = mount(MigrationCenter, { props: { accountId: 1 } });
    await flushPromises();
    await wrapper.get('[data-testid="migration-batch-8"]').trigger('click');
    await flushPromises();
    expect(wrapper.get('[data-testid="migration-media-1"]').text()).toContain(
      label
    );
    expect(wrapper.find('[data-testid="migration-scan-1"]').exists()).toBe(
      false
    );
    expect(
      wrapper.find('[data-testid="migration-media-recovery-1"]').exists()
    ).toBe(false);
  }
);
