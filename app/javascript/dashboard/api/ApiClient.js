/* global axios */

const DEFAULT_API_VERSION = 'v1';

class ApiClient {
  constructor(resource, options = {}) {
    this.apiVersion = `/api/${options.apiVersion || DEFAULT_API_VERSION}`;
    this.options = options;
    this.resource = resource;
  }

  get url() {
    return `${this.baseUrl()}/${this.resource}`;
  }

  // Bind an asynchronous workflow to the account captured when it started.
  urlForAccount(accountId) {
    const value = String(accountId);
    if (
      !this.options.accountScoped ||
      !/^[1-9]\d*$/.test(value) ||
      !Number.isSafeInteger(Number(value))
    ) {
      throw new Error('Invalid account context');
    }
    return `${this.apiVersion}/accounts/${value}/${this.resource}`;
  }

  // eslint-disable-next-line class-methods-use-this
  get isInsideSuperAdminAccountScopedURLs() {
    return window.location.pathname.includes('/super_admin/accounts');
  }

  // eslint-disable-next-line class-methods-use-this
  get accountIdFromRoute() {
    const isInsideAccountScopedURLs =
      window.location.pathname.includes('/app/accounts');

    if (isInsideAccountScopedURLs) {
      return window.location.pathname.split('/')[3];
    }

    if (this.isInsideSuperAdminAccountScopedURLs) {
      return window.location.pathname.split('/')[3];
    }

    return '';
  }

  baseUrl() {
    let url = this.apiVersion;

    if (this.options.enterprise) {
      url = `/enterprise${url}`;
    }

    if (this.options.accountScoped && this.accountIdFromRoute) {
      if (this.isInsideSuperAdminAccountScopedURLs) {
        return `/super_admin/api/accounts/${this.accountIdFromRoute}`;
      }

      url = `${url}/accounts/${this.accountIdFromRoute}`;
    }

    return url;
  }

  get() {
    return axios.get(this.url);
  }

  show(id) {
    return axios.get(`${this.url}/${id}`);
  }

  create(data) {
    return axios.post(this.url, data);
  }

  update(id, data) {
    return axios.patch(`${this.url}/${id}`, data);
  }

  delete(id) {
    return axios.delete(`${this.url}/${id}`);
  }
}

export default ApiClient;
