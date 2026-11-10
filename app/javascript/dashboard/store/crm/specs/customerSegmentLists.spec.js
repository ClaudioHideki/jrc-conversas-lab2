import { createStore } from 'vuex';
import leads from '../modules/leads';
import deals from '../modules/deals';
import activities from '../modules/activities';
import proposals from '../modules/proposals';

const apis = vi.hoisted(() => ({
  leadsAPI: { list: vi.fn() },
  dealsAPI: { list: vi.fn() },
  activitiesAPI: { list: vi.fn() },
  proposalsAPI: { list: vi.fn() },
  stagesAPI: {},
}));
vi.mock('dashboard/api/crm', () => apis);

it.each([
  ['leads', leads, 'fetchLeads', apis.leadsAPI],
  ['deals', deals, 'fetchDeals', apis.dealsAPI],
  ['activities', activities, 'fetchActivities', apis.activitiesAPI],
  ['proposals', proposals, 'fetchProposals', apis.proposalsAPI],
])(
  'keeps the latest %s filter and clears stale rows when a filtered request is denied',
  async (key, module, action, api) => {
    const store = createStore({
      modules: { list: { ...module, state: structuredClone(module.state) } },
    });
    let finishOld;
    api.list.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finishOld = resolve;
        })
    );
    const older = store.dispatch(`list/${action}`, {
      customer_segment_id: '1',
    });
    api.list.mockResolvedValueOnce({ data: [{ id: 2 }] });
    await store.dispatch(`list/${action}`, { customer_segment_id: '2' });
    finishOld({ data: [{ id: 1 }] });
    await older;
    expect(store.state.list[key]).toEqual([{ id: 2 }]);
    const silentError = vi.spyOn(console, 'error').mockImplementation(() => {});
    api.list.mockRejectedValueOnce({
      response: { status: 403, data: { error: 'Denied' } },
    });
    await store.dispatch(`list/${action}`, { customer_segment_id: '3' });
    expect(store.state.list[key]).toEqual([]);
    expect(store.state.list.isLoading).toBe(false);
    silentError.mockRestore();
  }
);
