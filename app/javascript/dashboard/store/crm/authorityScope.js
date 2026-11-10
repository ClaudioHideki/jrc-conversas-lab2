import { accountMembershipAccess } from 'dashboard/helper/accountMembershipAccess';

export const authorityScope = getters =>
  JSON.stringify([
    getters.getCurrentAccountId,
    getters.getCurrentUserID,
    getters.getCurrentRole,
    getters.getCurrentUser?.accounts?.map(accountMembershipAccess),
  ]);

export const hasCurrentAuthority = (state, getters) =>
  state.authorityScope === authorityScope(getters);
