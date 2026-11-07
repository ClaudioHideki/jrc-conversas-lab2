export const authorityScope = getters =>
  JSON.stringify([
    getters.getCurrentAccountId,
    getters.getCurrentUserID,
    getters.getCurrentRole,
    getters.getCurrentUser?.accounts,
  ]);

export const hasCurrentAuthority = (state, getters) =>
  state.authorityScope === authorityScope(getters);
