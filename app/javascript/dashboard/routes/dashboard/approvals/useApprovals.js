import { reactive } from 'vue';
import { approvalClient } from 'dashboard/api/approvals';
import { pagination } from './model';
export const useApprovals = () => {
  const state = reactive({
    accountId: null,
    context: null,
    rows: [],
    page: { total: 0, page: 1, limit: 25 },
    loading: false,
    error: null,
    success: false,
  });
  let generation = 0;
  const reset = accountId => {
    generation += 1;
    Object.assign(state, {
      accountId,
      context: null,
      rows: [],
      error: null,
      success: false,
      loading: false,
      page: { total: 0, page: 1, limit: 25 },
    });
  };
  const run = async fn => {
    generation += 1;
    const current = generation;
    const account = state.accountId;
    state.loading = true;
    state.error = null;
    state.success = false;
    try {
      const result = await fn(approvalClient(account));
      if (current !== generation || account !== state.accountId) return null;
      state.success = true;
      return result;
    } catch (error) {
      if (current !== generation) return null;
      state.error = {
        status: error.response?.status,
        code: error.response?.data?.error || error.response?.data?.code,
        details: error.response?.data?.errors,
      };
      return null;
    } finally {
      if (current === generation) state.loading = false;
    }
  };
  const loadContext = async () => {
    const result = await run(api => api.get('context'));
    if (result && Number(result.data.account_id) === Number(state.accountId))
      state.context = result.data;
  };
  const list = async (path, params) => {
    const result = await run(api => api.get(path, params));
    if (result) {
      state.rows = result.data;
      state.page = pagination(result);
    }
  };
  return { state, reset, run, list, loadContext };
};
