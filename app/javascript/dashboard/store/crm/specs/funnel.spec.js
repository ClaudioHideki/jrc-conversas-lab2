import { createStore } from 'vuex';
import deals from '../modules/deals';
import pipelines from '../modules/pipelines';
import { dealsAPI, stagesAPI, pipelinesAPI } from 'dashboard/api/crm';

vi.mock('dashboard/api/crm', () => ({
  dealsAPI: { list: vi.fn(), moveStage: vi.fn() },
  stagesAPI: { list: vi.fn() },
  pipelinesAPI: { list: vi.fn() },
}));

let store;
beforeEach(() => {
  store = createStore({
    modules: {
      jrcCrm: {
        namespaced: true,
        modules: {
          deals: { ...deals, state: structuredClone(deals.state) },
          pipelines: {
            ...pipelines,
            state: { pipelines: [{ id: 1 }, { id: 2 }], error: null },
          },
        },
      },
    },
  });
  stagesAPI.list.mockImplementation(async ({ pipeline_id: id }) => ({
    data: [{ id: id * 10, pipeline_id: id }],
  }));
  dealsAPI.list.mockResolvedValue({ data: [] });
});
const load = filters => store.dispatch('jrcCrm/deals/fetchKanbanData', filters);

describe('existing CRM funnel data contract', () => {
  it('loads stages from every pipeline when All pipelines is selected', async () => {
    await load({ pipeline_id: null });
    expect(stagesAPI.list).toHaveBeenCalledTimes(2);
    expect(
      store.getters['jrcCrm/deals/dealsByStage'].map(c => c.stage.id)
    ).toEqual([10, 20]);
    expect(store.getters['jrcCrm/deals/error']).toBeNull();
  });
  it('keeps empty stages visible and passes search/owner/pipeline to the API', async () => {
    await load({ pipeline_id: 2, owner_id: 3, search: 'Cliente' });
    expect(dealsAPI.list).toHaveBeenCalledWith({
      pipeline_id: 2,
      owner_id: 3,
      search: 'Cliente',
    });
    expect(store.getters['jrcCrm/deals/dealsByStage']).toEqual([
      { stage: { id: 20, pipeline_id: 2 }, deals: [] },
    ]);
  });
  it.each([401, 403, 500])(
    'shows HTTP %s as an error rather than an empty funnel',
    async status => {
      dealsAPI.list.mockRejectedValue({ response: { status } });
      await load({ pipeline_id: 1 });
      expect(store.getters['jrcCrm/deals/error']).toBeTruthy();
      expect(store.getters['jrcCrm/deals/isLoading']).toBe(false);
      expect(store.getters['jrcCrm/deals/dealsByStage']).toEqual([]);
    }
  );
  it('applies overdue and missing activity filters to real serialized records', async () => {
    dealsAPI.list.mockResolvedValue({
      data: [
        { id: 1, stage_id: 10, overdue: true, next_activity: null },
        {
          id: 2,
          stage_id: 10,
          overdue: false,
          next_activity: { is_overdue: true },
        },
        { id: 3, stage_id: 10, overdue: false, next_activity: null },
      ],
    });
    await load({ pipeline_id: 1, overdueOnly: true, noNextActivity: true });
    expect(store.getters['jrcCrm/deals/allDeals'].map(d => d.id)).toEqual([1]);
    await load({ pipeline_id: 1, overdueOnly: true });
    expect(store.getters['jrcCrm/deals/allDeals'].map(d => d.id)).toEqual([
      1, 2,
    ]);
  });
  it('does not replace the selected pipeline with a late previous request', async () => {
    let completeFirst;
    dealsAPI.list.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          completeFirst = resolve;
        })
    );
    const first = load({ pipeline_id: 1 });
    await load({ pipeline_id: 2 });
    completeFirst({ data: [{ id: 1, stage_id: 10 }] });
    await first;
    expect(store.getters['jrcCrm/deals/dealsByStage'][0].stage.id).toBe(20);
    expect(store.getters['jrcCrm/deals/allDeals']).toEqual([]);
  });
  it('keeps loading active until stages AND deals finish', async () => {
    let completeStages;
    stagesAPI.list.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          completeStages = resolve;
        })
    );
    const pending = load({ pipeline_id: 1 });
    await Promise.resolve();
    expect(store.getters['jrcCrm/deals/isLoading']).toBe(true);
    completeStages({ data: [] });
    await pending;
    expect(store.getters['jrcCrm/deals/isLoading']).toBe(false);
  });
  it('exposes pipeline failures and permits retry without stale pipeline data', async () => {
    pipelinesAPI.list.mockRejectedValueOnce({ response: { status: 500 } });
    await store.dispatch('jrcCrm/pipelines/fetchPipelines');
    expect(store.getters['jrcCrm/pipelines/error']).toBeTruthy();
    expect(store.getters['jrcCrm/pipelines/allPipelines']).toEqual([]);
    pipelinesAPI.list.mockResolvedValueOnce({ data: [{ id: 3 }] });
    await store.dispatch('jrcCrm/pipelines/fetchPipelines');
    expect(store.getters['jrcCrm/pipelines/error']).toBeNull();
    expect(store.getters['jrcCrm/pipelines/allPipelines']).toEqual([{ id: 3 }]);
  });
});
