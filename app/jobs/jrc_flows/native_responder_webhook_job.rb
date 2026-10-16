class JrcFlows::NativeResponderWebhookJob < WebhookJob
  discard_on JrcFlows::OwnershipGuard::Closed, JrcFlows::OwnershipEffects::Duplicate
  def perform(account_id, inbox_id, reference, url, payload)
    inbox = Inbox.find_by!(id: inbox_id, account_id: account_id)
    JrcFlows::NativeResponders.perform(inbox: inbox, path: 'automation-rule', reference: "native-rule-webhook:#{reference}", kind: 'EXTERNAL') do
      super(url, payload)
    end
  end
end
