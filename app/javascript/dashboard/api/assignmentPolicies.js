/* global axios */

import ApiClient from './ApiClient';

class AssignmentPolicies extends ApiClient {
  constructor() {
    super('assignment_policies', { accountScoped: true });
  }

  getInboxes(policyId) {
    return axios.get(`${this.url}/${policyId}/inboxes`);
  }

  inboxAssignmentPolicyUrl(inboxId) {
    const apiBase = this.isInsideSuperAdminAccountScopedURLs
      ? '/super_admin/api/accounts'
      : '/api/v1/accounts';
    return `${apiBase}/${this.accountIdFromRoute}/inboxes/${inboxId}/assignment_policy`;
  }

  setInboxPolicy(inboxId, policyId) {
    return axios.post(this.inboxAssignmentPolicyUrl(inboxId), {
      assignment_policy_id: policyId,
    });
  }

  getInboxPolicy(inboxId) {
    return axios.get(this.inboxAssignmentPolicyUrl(inboxId));
  }

  getInboxDiagnostics(inboxId) {
    return axios.get(
      this.inboxAssignmentPolicyUrl(inboxId).replace(
        '/assignment_policy',
        '/assignment_diagnostics'
      )
    );
  }

  removeInboxPolicy(inboxId) {
    return axios.delete(this.inboxAssignmentPolicyUrl(inboxId));
  }
}

export default new AssignmentPolicies();
