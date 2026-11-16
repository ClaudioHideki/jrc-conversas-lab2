class JrcBrokerLiveReceipt < ApplicationRecord
  self.filter_attributes += [:staged_bytes, :envelope, :access_token_sha256]
  belongs_to :account
  belongs_to :inbox
  belongs_to :user, optional: true
  belongs_to :access_token, optional: true
  belongs_to :message, optional: true
  belongs_to :blob, class_name: 'ActiveStorage::Blob', optional: true
  attr_readonly :account_id, :inbox_id, :organization_id, :integration_id, :instance_id, :broker_message_id,
                :destination_revision, :conversation_id, :envelope, :request_hash, :blob_id, :access_token_sha256

  def receiver
    token = access_token
    valid = user && token && ActiveSupport::SecurityUtils.secure_compare(access_token_sha256, Digest::SHA256.hexdigest(token.token))
    raise Pundit::NotAuthorizedError unless valid

    JrcBroker::LiveIngress.new(account: account, user: user, access_token: token)
  end

  def receipt_payload
    attributes.slice('organization_id', 'integration_id', 'instance_id', 'destination_revision', 'account_id', 'inbox_id',
                     'broker_message_id', 'conversation_id', 'message_id', 'request_hash', 'state').merge(
                       'protocol' => JrcBroker::LiveIngressContract::PROTOCOL, 'receipt_id' => id
                     )
  end
end
