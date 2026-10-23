/* global axios */

import ApiClient from './ApiClient';

class JrcCampaignsAPI extends ApiClient {
  constructor() {
    super('jrc_campaigns/campaigns', { accountScoped: true });
  }

  launch(id) {
    return axios.post(`${this.url}/${id}/launch`);
  }

  requestReview(id) {
    return axios.post(`${this.url}/${id}/request_review`);
  }

  approve(id, digest) {
    return axios.post(`${this.url}/${id}/approve`, { digest });
  }

  consents() {
    return axios.get(`${super.baseUrl()}/jrc_campaigns/consents`);
  }

  testAuthorizations() {
    return axios.get(`${super.baseUrl()}/jrc_campaigns/test_authorizations`);
  }

  createTestAuthorization(testAuthorization) {
    return axios.post(`${super.baseUrl()}/jrc_campaigns/test_authorizations`, {
      test_authorization: testAuthorization,
    });
  }

  revokeTestAuthorization(id) {
    return axios.delete(
      `${super.baseUrl()}/jrc_campaigns/test_authorizations/${id}`
    );
  }

  createConsent(consent) {
    return axios.post(`${super.baseUrl()}/jrc_campaigns/consents`, { consent });
  }

  revokeConsent(id) {
    return axios.delete(`${super.baseUrl()}/jrc_campaigns/consents/${id}`);
  }

  previewConsentImport(csv) {
    return axios.post(
      `${super.baseUrl()}/jrc_campaigns/consents/import_preview`,
      { csv }
    );
  }

  importConsents(csv, operatorConfirmed) {
    return axios.post(`${super.baseUrl()}/jrc_campaigns/consents/import_csv`, {
      csv,
      operator_confirmed: operatorConfirmed,
    });
  }

  pause(id) {
    return axios.post(`${this.url}/${id}/pause`);
  }

  resume(id) {
    return axios.post(`${this.url}/${id}/resume`);
  }

  cancel(id) {
    return axios.post(`${this.url}/${id}/cancel`);
  }

  duplicate(id) {
    return axios.post(`${this.url}/${id}/duplicate`);
  }

  audiencePreview(payload, options = {}) {
    const recipientOptions = Object.fromEntries(
      Object.entries(options).filter(([key]) =>
        [
          'include_recipients',
          'recipient_search',
          'recipient_page',
          'recipient_per_page',
        ].includes(key)
      )
    );
    return axios.post(`${this.url}/audience_preview`, {
      campaign: payload,
      ...recipientOptions,
    });
  }

  analytics(params = {}) {
    return axios.get(`${this.url}/analytics`, { params });
  }

  testMessage(payload) {
    return axios.post(`${this.url}/test_message`, { test_message: payload });
  }

  testDelivery(id) {
    return axios.get(`${super.baseUrl()}/jrc_campaigns/test_deliveries/${id}`);
  }

  preview(id) {
    return axios.get(`${this.url}/${id}/preview`);
  }

  report(id, params = {}) {
    return axios.get(`${this.url}/${id}/report`, { params });
  }

  exportUrl(id) {
    return `${this.url}/${id}/export`;
  }

  metadata() {
    return axios.get(`${super.baseUrl()}/jrc_campaigns/metadata`);
  }

  blacklists() {
    return axios.get(`${super.baseUrl()}/jrc_campaigns/blacklists`);
  }

  createBlacklist(payload) {
    return axios.post(`${super.baseUrl()}/jrc_campaigns/blacklists`, {
      blacklist: payload,
    });
  }

  deleteBlacklist(id) {
    return axios.delete(`${super.baseUrl()}/jrc_campaigns/blacklists/${id}`);
  }

  sanitizedLists() {
    return axios.get(`${super.baseUrl()}/jrc_campaigns/sanitized_lists`);
  }

  sanitizedList(id) {
    return axios.get(`${super.baseUrl()}/jrc_campaigns/sanitized_lists/${id}`);
  }

  createSanitizedList(payload) {
    return axios.post(
      `${super.baseUrl()}/jrc_campaigns/sanitized_lists`,
      payload
    );
  }

  deleteSanitizedList(id) {
    return axios.delete(
      `${super.baseUrl()}/jrc_campaigns/sanitized_lists/${id}`
    );
  }

  uploadMedia(file, kind) {
    const formData = new FormData();
    formData.append('file', file);
    formData.append('kind', kind);
    return axios.post(
      `${super.baseUrl()}/jrc_campaigns/media_assets`,
      formData,
      {
        headers: { 'Content-Type': 'multipart/form-data' },
      }
    );
  }
}

export default new JrcCampaignsAPI();
