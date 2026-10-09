/* global axios */
import { canonicalId } from '../routes/dashboard/serviceDesk/helpers/access';
import {
  ruleKinds,
  reportFilters,
} from '../routes/dashboard/serviceDesk/helpers/operationalRules.mjs';
const id = value => {
  const result = canonicalId(value);
  if (!result) throw new TypeError('Invalid identifier');
  return result;
};
const base = account => `/api/v1/accounts/${id(account)}/jrc_service_desk`;
const family = value => {
  if (!ruleKinds.includes(value)) throw new TypeError('Invalid rule family');
  return value;
};
const result = response => response.data;
const options = signal => ({ signal, timeout: 20000 });
export default {
  list: (account, unit, kind, signal) =>
    axios
      .get(`${base(account)}/operational_rules`, {
        ...options(signal),
        params: { unit_id: id(unit), kind: family(kind) },
      })
      .then(result),
  publish: (account, unit, kind, values, signal) =>
    axios
      .post(
        `${base(account)}/operational_rules`,
        {
          ...values,
          unit_id: id(unit),
          kind: family(kind),
        },
        options(signal)
      )
      .then(result),
  intake: (account, unit, signal) =>
    axios
      .get(`${base(account)}/intake_options`, {
        ...options(signal),
        params: { unit_id: id(unit) },
      })
      .then(result),
  report: (account, unit, query, signal) =>
    axios
      .get(`${base(account)}/operational_reports`, {
        ...options(signal),
        params: { ...reportFilters(query), unit_id: id(unit) },
      })
      .then(result),
  export: (account, unit, query, signal) =>
    axios
      .get(`${base(account)}/operational_reports/export`, {
        ...options(signal),
        params: { ...reportFilters(query), unit_id: id(unit) },
        responseType: 'blob',
      })
      .then(response => {
        if (!String(response.headers['content-type']).startsWith('text/csv'))
          throw new TypeError('Invalid export response');
        return response.data;
      }),
  recurrence: (account, unit, signal) =>
    axios
      .get(`${base(account)}/recurrence_suggestions`, {
        ...options(signal),
        params: { unit_id: id(unit) },
      })
      .then(result),
  preview: (account, unit, incident, batch, signal) =>
    axios
      .post(
        `${base(account)}/incidents/${id(incident)}/batch_preview`,
        {
          unit_id: id(unit),
          batch,
        },
        options(signal)
      )
      .then(result),
  batchReadback: (account, unit, incident, key, signal) =>
    axios
      .get(`${base(account)}/incidents/${id(incident)}/batch_result`, {
        ...options(signal),
        params: { unit_id: id(unit), idempotency_key: key },
      })
      .then(result),
  execute: (account, unit, incident, values, key, signal) =>
    axios
      .post(
        `${base(account)}/incidents/${id(incident)}/batches`,
        {
          ...values,
          unit_id: id(unit),
        },
        { ...options(signal), headers: { 'Idempotency-Key': key } }
      )
      .then(result),
};
