import { createStore } from 'vuex';
import { reactive } from 'vue';
import { beforeEach, expect, it, vi } from 'vitest';
import leads from '../modules/leads';
import activities from '../modules/activities';
import deals from '../modules/deals';
import pipelines from '../modules/pipelines';
import proposals from '../modules/proposals';
import { authorityScope } from '../authorityScope';
const apis = vi.hoisted(() => ({
  leadsAPI: {
    list: vi.fn(),
    show: vi.fn(),
    create: vi.fn(),
    convert: vi.fn(),
    lose: vi.fn(),
  },
  activitiesAPI: { list: vi.fn() },
  dealsAPI: { list: vi.fn(), show: vi.fn() },
  stagesAPI: { list: vi.fn() },
  pipelinesAPI: { list: vi.fn() },
  proposalsAPI: { list: vi.fn() },
}));
vi.mock('dashboard/api/crm', () => apis);
const modules = [
  ['proposals', proposals, 'fetchProposals', 'allProposals', apis.proposalsAPI],
  ['pipelines', pipelines, 'fetchPipelines', 'allPipelines', apis.pipelinesAPI],
  ['leads', leads, 'fetchLeads', 'allLeads', apis.leadsAPI],
  [
    'activities',
    activities,
    'fetchActivities',
    'allActivities',
    apis.activitiesAPI,
  ],
  ['deals', deals, 'fetchDeals', 'allDeals', apis.dealsAPI],
];
const mountStore = module => {
  const authority = reactive({
    account: 1,
    user: 7,
    role: 'administrator',
    grant: 1,
  });
  const store = createStore({
    getters: {
      getCurrentAccountId: () => authority.account,
      getCurrentUserID: () => authority.user,
      getCurrentRole: () => authority.role,
      getCurrentUser: () => ({
        accounts: [
          {
            id: authority.account,
            role: authority.role,
            custom_role_id: authority.grant,
            availability_status: authority.presence,
          },
        ],
      }),
    },
    modules: {
      list: { ...module, state: structuredClone(module.state) },
      jrcCrm: {
        namespaced: true,
        modules: {
          pipelines: {
            ...pipelines,
            state: {
              ...structuredClone(pipelines.state),
              authorityScope: authorityScope({
                getCurrentAccountId: 1,
                getCurrentUserID: 7,
                getCurrentRole: 'administrator',
                getCurrentUser: {
                  accounts: [
                    { id: 1, role: 'administrator', custom_role_id: 1 },
                  ],
                },
              }),
              pipelines: [{ id: 1 }],
            },
          },
        },
      },
    },
  });
  return { store, authority };
};
beforeEach(() => {
  vi.resetAllMocks();
  Object.values(apis).forEach(api => api.list?.mockResolvedValue({ data: [] }));
});

it.each(modules)(
  'hides a loaded %s cache immediately when the native actor or role changes without another fetch',
  async (key, module, action, getter, api) => {
    const { store, authority } = mountStore(module);
    api.list.mockResolvedValue({
      data: [{ id: 1, title: 'Synthetic native private cached row' }],
    });
    await store.dispatch(`list/${action}`);
    expect(store.getters[`list/${getter}`]).toHaveLength(1);
    authority.role = 'agent';
    authority.user = 99;
    expect(store.getters[`list/${getter}`]).toEqual([]);
    expect(store.getters['list/isLoading']).toBe(false);
  }
);

it.each(modules)(
  'does not commit a late %s list from a replaced native account even without a competing fetch',
  async (key, module, action, getter, api) => {
    const { store, authority } = mountStore(module);
    let finish;
    api.list.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const pending = store.dispatch(`list/${action}`);
    authority.account = 2;
    finish({ data: [{ id: 1, title: 'Synthetic prior account row' }] });
    await pending;
    expect(store.state.list[key]).toEqual([]);
    expect(store.getters[`list/${getter}`]).toEqual([]);
  }
);

it('does not leak lead lookup or deal aggregate aliases from an earlier native authority', async () => {
  const first = mountStore(leads);
  apis.leadsAPI.list.mockResolvedValue({ data: [{ id: 1 }] });
  await first.store.dispatch('list/fetchLeads');
  first.authority.grant = 2;
  expect(first.store.getters['list/leadById'](1)).toBeUndefined();
  const second = mountStore(deals);
  apis.dealsAPI.list.mockResolvedValue({
    data: [{ id: 1, stage_id: 10, status: 'open', overdue: true }],
  });
  await second.store.dispatch('list/fetchDeals');
  second.store.commit('list/SET_KANBAN_COLUMNS', [{ id: 10 }]);
  second.authority.grant = 2;
  expect([
    second.store.getters['list/dealById'](1),
    second.store.getters['list/openDeals'],
    second.store.getters['list/overdue'],
    second.store.getters['list/dealsByStage'],
  ]).toEqual([undefined, [], [], []]);
});

it('rejects a late native funnel and its stage metadata after account permissions changed', async () => {
  const { store, authority } = mountStore(deals);
  let finish;
  apis.dealsAPI.list.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  apis.stagesAPI.list.mockResolvedValue({ data: [{ id: 10, pipeline_id: 1 }] });
  const pending = store.dispatch('list/fetchKanbanData', { pipeline_id: 1 });
  authority.grant = 2;
  finish({ data: [{ id: 1, stage_id: 10 }] });
  await pending;
  expect([store.state.list.deals, store.state.list.kanbanColumns]).toEqual([
    [],
    [],
  ]);
});

it('does not replace a newer requested deal detail with a late earlier native response', async () => {
  const { store } = mountStore(deals);
  let finish;
  apis.dealsAPI.show.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  const first = store.dispatch('list/fetchDeal', 1);
  apis.dealsAPI.show.mockResolvedValueOnce({
    data: { id: 2, title: 'Synthetic selected deal' },
  });
  await store.dispatch('list/fetchDeal', 2);
  finish({ data: { id: 1, title: 'Synthetic obsolete detail' } });
  await first;
  expect(store.getters['list/currentDeal']).toEqual({
    id: 2,
    title: 'Synthetic selected deal',
  });
});

it('does not commit a native detail after actor authority changed', async () => {
  const { store, authority } = mountStore(deals);
  let finish;
  apis.dealsAPI.show.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  const pending = store.dispatch('list/fetchDeal', 1);
  authority.user = 99;
  finish({ data: { id: 1, title: 'Synthetic private previous actor detail' } });
  await pending;
  expect(store.state.list.currentDeal).toBeNull();
  expect(store.getters['list/currentDeal']).toBeNull();
});

it('does not let an old list replace a newer funnel or an old funnel replace a newer list', async () => {
  const { store } = mountStore(deals);
  let finish;
  apis.dealsAPI.list.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  const first = store.dispatch('list/fetchDeals');
  apis.stagesAPI.list.mockResolvedValue({ data: [{ id: 10 }] });
  apis.dealsAPI.list.mockResolvedValueOnce({ data: [{ id: 2, stage_id: 10 }] });
  await store.dispatch('list/fetchKanbanData', { pipeline_id: 1 });
  finish({ data: [{ id: 1 }] });
  await first;
  expect(store.getters['list/allDeals']).toEqual([{ id: 2, stage_id: 10 }]);
  apis.dealsAPI.list.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  const second = store.dispatch('list/fetchKanbanData', { pipeline_id: 1 });
  apis.dealsAPI.list.mockResolvedValueOnce({ data: [{ id: 3 }] });
  await store.dispatch('list/fetchDeals');
  finish({ data: [{ id: 2, stage_id: 10 }] });
  await second;
  expect(store.getters['list/allDeals']).toEqual([{ id: 3 }]);
  expect(store.getters['list/dealsByStage']).toEqual([]);
});

it('does not relabel cached deals using a new authority detail', async () => {
  const { store, authority } = mountStore(deals);
  apis.dealsAPI.list.mockResolvedValue({
    data: [{ id: 1, title: 'Synthetic former list' }],
  });
  await store.dispatch('list/fetchDeals');
  apis.dealsAPI.show.mockResolvedValue({
    data: { id: 1, title: 'Synthetic new detail' },
  });
  authority.user = 99;
  await store.dispatch('list/fetchDeal', 1);
  expect(store.getters['list/currentDeal'].title).toBe('Synthetic new detail');
  expect(store.getters['list/allDeals']).toEqual([]);
  expect(store.state.list.deals[0].title).toBe('Synthetic former list');
});

it('cancels the preceding selected detail when the detail is closed', async () => {
  const { store } = mountStore(deals);
  let finish;
  apis.dealsAPI.show.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  const pending = store.dispatch('list/fetchDeal', 1);
  await store.dispatch('list/fetchDeal', null);
  finish({ data: { id: 1 } });
  await pending;
  expect(store.getters['list/currentDeal']).toBeNull();
  expect(store.getters['list/isLoading']).toBe(false);
});

it('keeps native list filters while ignoring an error from the former authority', async () => {
  const { store, authority } = mountStore(activities);
  let reject;
  apis.activitiesAPI.list.mockImplementationOnce(
    () =>
      new Promise((_resolve, fail) => {
        reject = fail;
      })
  );
  const filters = { customer_segment_id: 10, page: 2 };
  const pending = store.dispatch('list/fetchActivities', filters);
  expect(apis.activitiesAPI.list).toHaveBeenCalledWith(filters);
  authority.account = 2;
  reject({
    response: { status: 403, data: { error: 'Synthetic old private error' } },
  });
  await pending;
  expect(store.state.list.error).toBeNull();
  expect(store.getters['list/error']).toBeNull();
});

it('does not refresh a different account after a native lead creation already finished', async () => {
  const { store, authority } = mountStore(leads);
  let finish;
  apis.leadsAPI.create.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  const pending = store.dispatch('list/createLead', {
    title: 'Synthetic native lead',
  });
  authority.account = 2;
  finish({ data: { id: 1 } });
  await pending;
  expect(apis.leadsAPI.list).not.toHaveBeenCalled();
});

it('hides loaded lead detail and ignores its late predecessor', async () => {
  const { store, authority } = mountStore(leads);
  let finish;
  apis.leadsAPI.show.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  const pending = store.dispatch('list/fetchLead', 1);
  apis.leadsAPI.show.mockResolvedValueOnce({ data: { id: 2 } });
  await store.dispatch('list/fetchLead', 2);
  finish({ data: { id: 1 } });
  await pending;
  expect(store.getters['list/currentLead']).toEqual({ id: 2 });
  authority.user = 99;
  expect(store.getters['list/currentLead']).toBeNull();
});

it.each(modules)(
  'retains a loaded %s cache across native availability refresh without ignoring later grant changes',
  async (_key, module, action, getter, api) => {
    const { store, authority } = mountStore(module);
    api.list.mockResolvedValue({ data: [{ id: 1 }] });
    await store.dispatch(`list/${action}`);
    authority.presence = 'online';
    expect(store.getters[`list/${getter}`]).toEqual([{ id: 1 }]);
    authority.presence = 'offline';
    expect(store.getters[`list/${getter}`]).toEqual([{ id: 1 }]);
    authority.grant = 2;
    expect(store.getters[`list/${getter}`]).toEqual([]);
  }
);
