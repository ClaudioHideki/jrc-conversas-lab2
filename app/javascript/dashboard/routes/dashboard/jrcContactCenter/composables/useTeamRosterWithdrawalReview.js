import { computed, onBeforeUnmount, reactive, watch } from 'vue';

export const teamRosterReviewAuthority = (user, accountId) => {
  const member = user?.accounts?.find(
    row => String(row.id) === String(accountId)
  );
  return {
    userId: user?.id,
    role: member?.role,
    customRoleId: member?.custom_role_id,
    permissions: member?.permissions,
    contactCenterEligible: member?.contact_center_eligible,
  };
};

// An in-memory, draft-bound receipt. The server recomputes impact and authority on every retry.
export const useTeamRosterWithdrawalReview = ({
  accountId,
  teamId,
  agentsList,
  authority,
}) => {
  const state = reactive({ review: null, confirmed: false, error: false });
  let reviewedKey = '';
  let generation = 0;
  const binding = () =>
    JSON.stringify([
      String(accountId.value),
      String(teamId.value || ''),
      [...agentsList.value].map(String).sort(),
      authority.value,
    ]);
  const fingerprint = () => JSON.stringify([generation, binding()]);
  const reset = () => {
    reviewedKey = '';
    Object.assign(state, { review: null, confirmed: false, error: false });
  };
  const clear = () => {
    generation += 1;
    reset();
  };
  const canSave = computed(
    () =>
      !state.error &&
      (!state.review ||
        (state.confirmed === true && reviewedKey === fingerprint()))
  );
  const handleError = (error, requestKey) => {
    if (requestKey !== fingerprint()) return true;
    if (error?.response?.data?.error !== 'team_roster_confirmation_required') {
      if ([401, 403, 404].includes(error?.response?.status)) clear();
      return false;
    }
    reset();
    const review = error.response.data.review;
    const valid =
      review &&
      String(review.account_id) === String(accountId.value) &&
      String(review.team_id) === String(teamId.value) &&
      review.operation === 'update' &&
      typeof review.team_name === 'string' &&
      Array.isArray(review.queues) &&
      review.queues.length > 0 &&
      review.queues.every(
        row =>
          /^[1-9]\d*$/.test(String(row.queue_id)) &&
          /^[1-9]\d*$/.test(String(row.unit_id)) &&
          typeof row.queue_name === 'string' &&
          Number.isSafeInteger(row.previous_count) &&
          row.previous_count > 0 &&
          row.remaining_count === 0
      ) &&
      new Set(review.queues.map(row => String(row.queue_id))).size ===
        review.queues.length &&
      typeof review.review_token === 'string' &&
      review.review_token.length > 0 &&
      review.review_token.length <= 4096;
    if (valid) {
      state.review = review;
      reviewedKey = requestKey;
    } else state.error = true;
    return true;
  };
  const options = () =>
    state.review && canSave.value
      ? {
          managerConfirmation: {
            confirmed: true,
            review_token: state.review.review_token,
          },
        }
      : {};
  watch(binding, clear, { flush: 'sync' });
  onBeforeUnmount(clear);
  return { state, canSave, handleError, options, clear, fingerprint };
};
