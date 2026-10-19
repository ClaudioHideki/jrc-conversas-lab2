class JrcFlowEffectReceipt < ApplicationRecord
  belongs_to :account
  belongs_to :inbox
  belongs_to :conversation

  def verify!(conversation:, user:, proof:, request_hash:)
    same = conversation_id == conversation.id && actor_user_id == user.id && self.request_hash == request_hash
    same &&= ActiveSupport::SecurityUtils.secure_compare(dispatch_proof_hash, Digest::SHA256.hexdigest(proof))
    raise ArgumentError, 'receipt_conflict' unless same

    JrcDomainCommands::ResourceScope.new(account: account, user: user).authorize_result!(domain_result) if operation == 'domain'
    self
  end

  def protocol_receipt
    receipt = attributes.slice('account_id', 'inbox_id', 'organization_id', 'operation_id', 'remote_contact_id', 'contact_inbox_id',
                               'actor_user_id', 'routing_source_hash', 'operation', 'resource_id', 'resource_revision', 'request_hash',
                               'dispatch_proof_hash', 'control_revision_before', 'control_revision_after', 'message_id')
                        .merge('protocol' => JrcFlowEffects::Request::PROTOCOL, 'state' => 'CONFIRMED', 'conversation_id' => remote_conversation_id)
    receipt['domain_result'] = domain_result if operation == 'domain'
    receipt
  end
end
