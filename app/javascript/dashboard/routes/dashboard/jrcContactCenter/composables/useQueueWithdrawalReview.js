import { computed, onBeforeUnmount, reactive, watch } from 'vue';

// The receipt stays in memory and only binds a reviewed draft; it never grants authority.
export const useQueueWithdrawalReview = ({
  accountId,
  resource,
  record,
  draft,
  allowed,
}) => {
  const state = reactive({
    review: null,
    confirmed: false,
    fingerprint: '',
    error: false,
  });
  const fingerprint = () =>
    JSON.stringify([
      String(accountId.value),
      resource.value,
      String(record.value?.id || ''),
      draft.value,
    ]);
  const clear = () =>
    Object.assign(state, {
      review: null,
      confirmed: false,
      fingerprint: '',
      error: false,
    });
  const canSave = computed(
    () =>
      !state.error &&
      (!state.review ||
        (state.confirmed === true && state.fingerprint === fingerprint()))
  );
  const handleError = error => {
    if (error?.response?.data?.error !== 'last_eligible_confirmation_required')
      return false;
    clear();
    const review = error.response.data.review;
    const valid =
      allowed.value &&
      resource.value === 'memberships' &&
      record.value?.id &&
      review &&
      String(review.account_id) === String(accountId.value) &&
      String(review.membership_id) === String(record.value.id) &&
      String(review.queue_id) === String(record.value.queue_id) &&
      typeof review.queue_name === 'string' &&
      review.previous_count === 1 &&
      review.remaining_count === 0 &&
      typeof review.review_token === 'string' &&
      review.review_token.length > 0 &&
      review.review_token.length <= 4096;
    if (!valid) state.error = true;
    else {
      state.review = review;
      state.fingerprint = fingerprint();
    }
    return true;
  };
  const options = () =>
    state.review && canSave.value
      ? {
          manager_confirmation: {
            confirmed: true,
            review_token: state.review.review_token,
          },
        }
      : {};
  watch(() => [fingerprint(), allowed.value], clear);
  onBeforeUnmount(clear);
  return { state, canSave, handleError, options, clear };
};
