import { describe, it, expect, vi, beforeEach } from 'vitest';
import API from 'dashboard/api/jrcRelationship';

describe('Relationship account context', () => {
  let axios;
  beforeEach(() => {
    axios = {
      get: vi.fn().mockResolvedValue({ data: {} }),
      post: vi.fn().mockResolvedValue({ data: {} }),
      patch: vi.fn().mockResolvedValue({ data: {} }),
    };
    vi.stubGlobal('axios', axios);
  });
  it('CS-01/CS-10 binds every request to the explicit account', async () => {
    await API.portfolio('12', { mode: 'mine' });
    await API.portfolio('13', { mode: 'mine' });
    expect(axios.get.mock.calls.map(([url]) => url)).toEqual([
      '/api/v1/accounts/12/relationship/portfolio',
      '/api/v1/accounts/13/relationship/portfolio',
    ]);
  });
  it('rejects invalid context before making a request', () => {
    [0, -1, undefined, '1/portfolio', '1e2', '01', 'NaN'].forEach(id => {
      expect(() => API.metadata(id)).toThrow('Invalid account context');
    });
    expect(axios.get).not.toHaveBeenCalled();
  });
  it('preserves cancellation options on a scoped request', async () => {
    const controller = new AbortController();
    await API.customer('12', 18, { signal: controller.signal });
    expect(axios.get).toHaveBeenCalledWith(
      '/api/v1/accounts/12/relationship/portfolio/18',
      { signal: controller.signal }
    );
  });
  it('CS-08 updates an assignment without creating another identity', async () => {
    await API.saveAssignment(12, { owner_id: 24 }, 18);
    expect(axios.patch).toHaveBeenCalledWith(
      '/api/v1/accounts/12/relationship/portfolio/18',
      { assignment: { owner_id: 24 } }
    );
    expect(axios.post).not.toHaveBeenCalled();
  });
  it('REL-007 approval delegates to the native opportunity action', async () => {
    await API.opportunity(12, 'expansion', 30, { pipeline_id: 2, stage_id: 3 });
    expect(axios.post).toHaveBeenCalledWith(
      '/api/v1/accounts/12/relationship/records/expansion/30/opportunity',
      { pipeline_id: 2, stage_id: 3 }
    );
  });
  it('binds operational lists and writes to the existing CRM endpoints in the explicit account', async () => {
    await API.operationsQueues(12);
    await API.operationsPolicies(12);
    await API.saveOperationsQueue(12, { name: 'CS' });
    await API.saveOperationsPolicy(13, { first_action_minutes: 240 }, 9);
    expect(axios.get.mock.calls.map(([url]) => url)).toEqual([
      '/api/v1/accounts/12/crm/operations_queues', '/api/v1/accounts/12/crm/operations_sla_policies',
    ]);
    expect(axios.post).toHaveBeenCalledWith('/api/v1/accounts/12/crm/operations_queues', { operations_queue: { name: 'CS' } });
    expect(axios.patch).toHaveBeenCalledWith('/api/v1/accounts/13/crm/operations_sla_policies/9', { operations_sla_policy: { first_action_minutes: 240 } });
  });
  it('rejects invalid account contexts for the operational controls', () => {
    expect(() => API.operationsQueues('1/other')).toThrow('Invalid account context');
    expect(() => API.saveOperationsPolicy(0, {})).toThrow('Invalid account context');
    expect(axios.get).not.toHaveBeenCalled();
    expect(axios.post).not.toHaveBeenCalled();
  });
  it('binds bulk actions, surveys and exports to their native scoped resources',async()=>{
    await API.portfolioBatch(12,[19],{operation:'activity',request_id:'same-retry'});
    await API.deliverSurvey(12,30,55);await API.nativeCsat(12,19,55);await API.surveyLink(12,30);await API.exportHistory(12,{assignment_id:19});
    expect(axios.post).toHaveBeenCalledWith('/api/v1/accounts/12/relationship/portfolio/batch',{ids:[19],operation:'activity',request_id:'same-retry'});
    expect(axios.post).toHaveBeenCalledWith('/api/v1/accounts/12/relationship/surveys/30/deliver',{conversation_id:55});
    expect(axios.post).toHaveBeenCalledWith('/api/v1/accounts/12/relationship/portfolio/19/native_csat',{conversation_id:55});
    expect(axios.get).toHaveBeenCalledWith('/api/v1/accounts/12/relationship/export_history',{params:{assignment_id:19},responseType:'blob'});
  });
});
