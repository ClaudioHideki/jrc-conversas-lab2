export const isWaitingStatus = status =>
  ['waiting_customer', 'waiting_finance'].includes(status);

export const validWaitingReview = form =>
  typeof form.waiting_reason === 'string' &&
  !!form.waiting_reason?.trim() &&
  typeof form.next_step === 'string' &&
  !!form.next_step?.trim() &&
  !!form.return_at &&
  new Date(form.return_at).getTime() > Date.now();
