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

  taxonomies(params = {}) {
    return axios.get(`${this.url}/taxonomies`, { params });
  }

  saveTaxonomy(taxonomy, id = null) {
    return id
      ? axios.patch(`${this.url}/taxonomies/${id}`, { taxonomy })
      : axios.post(`${this.url}/taxonomies`, { taxonomy });
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

  records(id, params) {
    return axios.get(`${this.url}/companies/${id}/records`, { params });
  }

  timeline(id, params = {}, type = 'companies') {
    return axios.get(`${this.url}/${type}/${id}/timeline`, { params });
  }

  contacts(params = {}) {
    return axios.get(`${this.url}/contacts`, { params });
  }

  contact(id) {
    return axios.get(`${this.url}/contacts/${id}`);
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

  contactOverview(id) {
    return axios.get(`${this.url}/contacts/${id}/overview`);
  }

  saveContact(contact, id = null, options = {}) {
    const body = { contact, ...options };
    return id
      ? axios.patch(`${this.url}/contacts/${id}`, body)
      : axios.post(`${this.url}/contacts`, body);
  }

  duplicates(id) {
    return axios.get(`${this.url}/contacts/${id}/duplicates`);
  }

  merge(id, sourceContactId) {
    return axios.post(`${this.url}/contacts/${id}/merge`, {
      source_contact_id: sourceContactId,
      confirm: true,
    });
  }

  savePoint(contactId, contactPoint, id = null) {
    const url = `${this.url}/contacts/${contactId}/contact_points`;
    return id
      ? axios.patch(`${url}/${id}`, { contact_point: contactPoint })
      : axios.post(url, { contact_point: contactPoint });
  }

  removePoint(contactId, id) {
    return axios.delete(
      `${this.url}/contacts/${contactId}/contact_points/${id}`
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
