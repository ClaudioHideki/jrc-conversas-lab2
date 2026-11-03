/* global axios */
import ApiClient from './ApiClient';
class CustomerAPI extends ApiClient {
  constructor() {
    super('customers', { accountScoped: true });
  }

  metadata(options = {}) {
    const { accountId, ...requestOptions } = options;
    const url =
      accountId === undefined ? this.url : this.urlForAccount(accountId);
    return axios.get(`${url}/metadata`, requestOptions);
  }

  identity(params) {
    return axios.get(`${this.url}/identity`, { params });
  }

  economicGroupUrl(options = {}) {
    const url =
      options.accountId === undefined
        ? this.url
        : this.urlForAccount(options.accountId);
    return `${url}/economic_groups`;
  }

  economicGroups(params = {}, options = {}) {
    const { accountId, ...requestOptions } = options;
    return axios.get(this.economicGroupUrl({ accountId }), {
      ...requestOptions,
      params,
    });
  }

  economicGroup(id, options = {}) {
    const { accountId, ...requestOptions } = options;
    return axios.get(
      `${this.economicGroupUrl({ accountId })}/${id}`,
      requestOptions
    );
  }

  saveEconomicGroup(economicGroup, id = null, options = {}) {
    const { accountId, ...requestOptions } = options;
    const url = this.economicGroupUrl({ accountId });
    return id
      ? axios.patch(
          `${url}/${id}`,
          { economic_group: economicGroup },
          requestOptions
        )
      : axios.post(url, { economic_group: economicGroup }, requestOptions);
  }

  economicGroupRecords(id, view, params = {}, options = {}) {
    const { accountId, ...requestOptions } = options;
    return axios.get(`${this.economicGroupUrl({ accountId })}/${id}/${view}`, {
      ...requestOptions,
      params,
    });
  }

  assignEconomicGroup(id, values, options = {}) {
    const { accountId, ...requestOptions } = options;
    return axios.post(
      `${this.economicGroupUrl({ accountId })}/${id}/assign`,
      values,
      requestOptions
    );
  }

  deleteEconomicGroup(id, revision, options = {}) {
    const { accountId, ...requestOptions } = options;
    return axios.delete(`${this.economicGroupUrl({ accountId })}/${id}`, {
      ...requestOptions,
      data: { confirm: true, revision },
    });
  }

  taxonomyUrl(options = {}) {
    return `${options.accountId === undefined ? this.url : this.urlForAccount(options.accountId)}/taxonomies`;
  }

  taxonomies(params = {}, options = {}) {
    const { accountId, ...requestOptions } = options;
    return axios.get(this.taxonomyUrl({ accountId }), {
      ...requestOptions,
      params,
    });
  }

  taxonomy(id, options = {}) {
    const { accountId, ...requestOptions } = options;
    return axios.get(
      `${this.taxonomyUrl({ accountId })}/${id}`,
      requestOptions
    );
  }

  saveTaxonomy(taxonomy, id = null, options = {}) {
    const { accountId, ...requestOptions } = options;
    const url = this.taxonomyUrl({ accountId });
    return id
      ? axios.patch(`${url}/${id}`, { taxonomy }, requestOptions)
      : axios.post(url, { taxonomy }, requestOptions);
  }

  segmentPreview(taxonomy, params = {}, options = {}) {
    const { accountId, ...requestOptions } = options;
    return axios.post(
      `${this.taxonomyUrl({ accountId })}/preview`,
      { taxonomy, ...params },
      requestOptions
    );
  }

  segmentRecords(id, view, params = {}, options = {}) {
    const { accountId, ...requestOptions } = options;
    return axios.get(`${this.taxonomyUrl({ accountId })}/${id}/${view}`, {
      ...requestOptions,
      params,
    });
  }

  segmentOverride(id, choice, options = {}) {
    const { accountId, ...requestOptions } = options;
    return axios.post(
      `${this.taxonomyUrl({ accountId })}/${id}/set_override`,
      choice,
      requestOptions
    );
  }

  removeSegmentOverride(id, choiceId, options = {}) {
    const { accountId, ...requestOptions } = options;
    return axios.delete(
      `${this.taxonomyUrl({ accountId })}/${id}/overrides/${choiceId}`,
      requestOptions
    );
  }

  deleteTaxonomy(id, options = {}) {
    const { accountId, ...requestOptions } = options;
    return axios.delete(`${this.taxonomyUrl({ accountId })}/${id}`, {
      ...requestOptions,
      data: { confirm: true },
    });
  }

  companies(params = {}, options = {}) {
    const { accountId, ...requestOptions } = options;
    const url =
      accountId === undefined ? this.url : this.urlForAccount(accountId);
    return axios.get(`${url}/companies`, { ...requestOptions, params });
  }

  company(id, options = {}) {
    const { accountId, ...requestOptions } = options;
    const url =
      accountId === undefined ? this.url : this.urlForAccount(accountId);
    return axios.get(`${url}/companies/${id}`, requestOptions);
  }

  saveCompany(company, id = null) {
    return id
      ? axios.patch(`${this.url}/companies/${id}`, { company })
      : axios.post(`${this.url}/companies`, { company });
  }

  overview(id, options = {}) {
    const { accountId, ...requestOptions } = options;
    const url =
      accountId === undefined ? this.url : this.urlForAccount(accountId);
    return axios.get(`${url}/companies/${id}/overview`, requestOptions);
  }

  backoffice(id, params = {}, options = {}) {
    const { accountId, ...requestOptions } = options;
    const url =
      accountId === undefined ? this.url : this.urlForAccount(accountId);
    return axios.get(`${url}/companies/${id}/backoffice`, {
      ...requestOptions,
      params,
    });
  }

  relationships(id) {
    return axios.get(`${this.url}/companies/${id}/relationships`);
  }

  records(id, params, options = {}) {
    const { accountId, ...requestOptions } = options;
    const url =
      accountId === undefined ? this.url : this.urlForAccount(accountId);
    return axios.get(`${url}/companies/${id}/records`, {
      ...requestOptions,
      params,
    });
  }

  contactRecords(id, params, options = {}) {
    const { accountId, ...requestOptions } = options;
    const url =
      accountId === undefined ? this.url : this.urlForAccount(accountId);
    return axios.get(`${url}/contacts/${id}/records`, {
      ...requestOptions,
      params,
    });
  }

  contactCompanyHistory(id, params = {}, options = {}) {
    const { accountId, ...requestOptions } = options;
    const url =
      accountId === undefined ? this.url : this.urlForAccount(accountId);
    return axios.get(`${url}/contacts/${id}/company_history`, {
      ...requestOptions,
      params,
    });
  }

  timeline(id, params = {}, type = 'companies', options = {}) {
    const { accountId, ...requestOptions } = options;
    const url =
      accountId === undefined ? this.url : this.urlForAccount(accountId);
    return axios.get(`${url}/${type}/${id}/timeline`, {
      ...requestOptions,
      params,
    });
  }

  contacts(params = {}, options = {}) {
    const { accountId, ...requestOptions } = options;
    const url =
      accountId === undefined ? this.url : this.urlForAccount(accountId);
    return axios.get(`${url}/contacts`, { ...requestOptions, params });
  }

  contact(id, options = {}) {
    const { accountId, ...requestOptions } = options;
    const url =
      accountId === undefined ? this.url : this.urlForAccount(accountId);
    return axios.get(`${url}/contacts/${id}`, requestOptions);
  }

  signingIdentity(accountId, contactId, options = {}) {
    return axios.get(
      `${this.urlForAccount(accountId)}/contacts/${contactId}/signing_identity`,
      options
    );
  }

  saveSigningIdentity(accountId, contactId, body) {
    return axios.patch(
      `${this.urlForAccount(accountId)}/contacts/${contactId}/signing_identity`,
      body
    );
  }

  contactOverview(id, options = {}) {
    const { accountId, ...requestOptions } = options;
    const url =
      accountId === undefined ? this.url : this.urlForAccount(accountId);
    return axios.get(`${url}/contacts/${id}/overview`, requestOptions);
  }

  saveContact(contact, id = null, options = {}, request = {}) {
    const body = { contact, ...options };
    const { accountId, ...requestOptions } = request;
    const url =
      accountId === undefined ? this.url : this.urlForAccount(accountId);
    return id
      ? axios.patch(`${url}/contacts/${id}`, body, requestOptions)
      : axios.post(`${url}/contacts`, body, requestOptions);
  }

  duplicates(id, options = {}) {
    const { accountId, ...requestOptions } = options;
    const url =
      accountId === undefined ? this.url : this.urlForAccount(accountId);
    return axios.get(`${url}/contacts/${id}/duplicates`, requestOptions);
  }

  merge(id, sourceContactId, options = {}) {
    const { accountId, ...requestOptions } = options;
    const url =
      accountId === undefined ? this.url : this.urlForAccount(accountId);
    return axios.post(
      `${url}/contacts/${id}/merge`,
      {
        source_contact_id: sourceContactId,
        confirm: true,
      },
      requestOptions
    );
  }

  savePoint(contactId, contactPoint, id = null, options = {}) {
    const { accountId, ...requestOptions } = options;
    const base =
      accountId === undefined ? this.url : this.urlForAccount(accountId);
    const url = `${base}/contacts/${contactId}/contact_points`;
    return id
      ? axios.patch(
          `${url}/${id}`,
          { contact_point: contactPoint },
          requestOptions
        )
      : axios.post(url, { contact_point: contactPoint }, requestOptions);
  }

  removePoint(contactId, id, options = {}) {
    const { accountId, ...requestOptions } = options;
    const url =
      accountId === undefined ? this.url : this.urlForAccount(accountId);
    return axios.delete(
      `${url}/contacts/${contactId}/contact_points/${id}`,
      requestOptions
    );
  }

  saveAddress(companyId, address, id = null) {
    const url = `${this.url}/companies/${companyId}/addresses`;
    return id
      ? axios.patch(`${url}/${id}`, { address })
      : axios.post(url, { address });
  }

  removeAddress(companyId, id) {
    return axios.delete(`${this.url}/companies/${companyId}/addresses/${id}`);
  }

  importCompanies(file, token = null) {
    const body = new FormData();
    body.append('file', file);
    if (token) body.append('token', token);
    return axios.post(
      `${this.url}/imports/${token ? 'apply' : 'preview'}`,
      body
    );
  }
}
export default new CustomerAPI();
