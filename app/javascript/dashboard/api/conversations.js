/* global axios */
import ApiClient from './ApiClient';

class ConversationApi extends ApiClient {
  constructor() {
    super('conversations', { accountScoped: true });
  }

  getLabels(conversationID) {
    return axios.get(`${this.url}/${conversationID}/labels`);
  }

  updateLabels(conversationID, labels) {
    return axios.post(`${this.url}/${conversationID}/labels`, { labels });
  }

  getUnreadCounts() {
    return axios.get(`${this.url}/unread_counts`);
  }

  sharedContext(accountId, inboxScope) {
    return axios.get(
      `${this.apiVersion}/accounts/${accountId}/conversations/meta`,
      {
        timeout: 30000,
        params: {
          assignee_type: 'mine_or_shared',
          include_participating: true,
          inbox_scope: inboxScope,
        },
      }
    );
  }
}

export default new ConversationApi();
