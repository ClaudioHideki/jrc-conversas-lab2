import { reactive } from 'vue';
import { approvalClient } from 'dashboard/api/approvals';
import { pagination } from './model';
export const useApprovals = (currentScope = () => null) => {
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
  let disposed = false;
  const invalidate = () => {
    generation += 1;
    state.loading = false;
    state.success = false;
  };
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
    if (disposed) return null;
    generation += 1;
    const current = generation;
    const account = state.accountId;
    const scope = currentScope();
    const isCurrent = () =>
      !disposed &&
      current === generation &&
      account === state.accountId &&
      scope === currentScope();
    state.loading = true;
    state.error = null;
    state.success = false;
    try {
      const result = await fn(approvalClient(account));
      if (!isCurrent()) return null;
      state.success = true;
      return result;
    } catch (error) {
      if (!isCurrent()) return null;
      state.error = {
        status: error.response?.status,
        code: error.response?.data?.error || error.response?.data?.code,
        details: error.response?.data?.errors,
      };
      return null;
    } finally {
      if (isCurrent()) state.loading = false;
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
  const dispose = () => {
    disposed = true;
    reset(null);
  };
  return { state, reset, run, list, loadContext, invalidate, dispose };
};
