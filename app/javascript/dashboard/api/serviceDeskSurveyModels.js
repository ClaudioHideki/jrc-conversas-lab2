/* global axios */
// Explicit Account + abort signal: an in-flight request never follows a tenant switch.
const id = value => {
  if (!/^[1-9]\d{0,17}$/.test(String(value)))
    throw new Error('Invalid survey identifier');
  return String(value);
};
const base = account =>
  `/api/v1/accounts/${id(account)}/relationship/survey_models`;
export default {
  list: (account, unit, page = 1, options = {}) =>
    axios.get(base(account), {
      ...options,
      params: { unit_id: id(unit), page },
    }),
  lookup: (account, unit, code, options = {}) =>
    axios.get(base(account), {
      ...options,
      params: { unit_id: id(unit), code },
    }),
  options: (account, unit, options = {}) =>
    axios.get(`${base(account)}/options`, {
      ...options,
      params: { unit_id: id(unit) },
    }),
  get: (account, model, options = {}) =>
    axios.get(`${base(account)}/${id(model)}`, options),
  save: (account, payload, model, version, options = {}) =>
    model
      ? axios.patch(
          `${base(account)}/${id(model)}`,
          { payload, lock_version: version },
          options
        )
      : axios.post(base(account), { payload }, options),
  validate: (account, model, options = {}) =>
    axios.post(`${base(account)}/${id(model)}/validate`, {}, options),
  publish: (account, model, version, requestKey, options = {}) =>
    axios.post(
      `${base(account)}/${id(model)}/publish`,
      { lock_version: version, request_key: requestKey },
      options
    ),
  duplicate: (account, model, options = {}) =>
    axios.post(`${base(account)}/${id(model)}/duplicate`, {}, options),
  deactivate: (account, model, version, options = {}) =>
    axios.post(
      `${base(account)}/${id(model)}/deactivate`,
      { lock_version: version },
      options
    ),
  history: (account, model, options = {}) =>
    axios.get(`${base(account)}/${id(model)}/history`, options),
  dispatch: (account, model, ticket, options = {}) =>
    axios.post(
      `${base(account)}/${id(model)}/dispatch`,
      { ticket_id: id(ticket) },
      options
    ),
};
