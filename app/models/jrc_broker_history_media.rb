class JrcBrokerHistoryMedia < ApplicationRecord
  self.table_name = 'jrc_broker_history_media'
  belongs_to :account
  belongs_to :inbox
  belongs_to :user, optional: true
  belongs_to :access_token, optional: true
  belongs_to :message, optional: true
  belongs_to :receipt, class_name: 'JrcBrokerHistoryReceipt', optional: true
  belongs_to :blob, class_name: 'ActiveStorage::Blob'
  attr_readonly :account_id, :inbox_id, :organization_id, :integration_id, :instance_id, :destination_revision,
                :history_account_identity, :reference_id, :descriptor, :descriptor_hash, :blob_id,
                :user_id, :access_token_id, :access_token_sha256

  def scope_input
    attributes.slice('organization_id', 'integration_id', 'instance_id', 'destination_revision', 'history_account_identity')
  end

  def importer
    original_token = access_token
    valid = user && original_token &&
            ActiveSupport::SecurityUtils.secure_compare(access_token_sha256, Digest::SHA256.hexdigest(original_token.token))
    raise Pundit::NotAuthorizedError unless valid

    JrcBroker::HistorySyncV2.new(account: account, user: user, access_token: access_token)
  end
end
