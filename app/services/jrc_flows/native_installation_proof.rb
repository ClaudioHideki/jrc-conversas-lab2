require 'digest'
class JrcFlows::NativeInstallationProof
  class Denied < StandardError; end
  KEYS = %w[audience grantId operationNonce proofNonce expectedGeneration registrationId registrationRevision credentialId credentialRevision
            destinationRevision accountCredentialVersion accountId tupleDigest].freeze
  def call(bearer:, request:)
    raise Denied unless bearer.is_a?(String) && /\A[A-Za-z0-9_-]{43}\z/.match?(bearer) && request.is_a?(Hash) && request.keys.sort == KEYS.sort
    raise Denied unless %w[FLOW_INSTALLATION_CLAIM FLOW_INSTALLATION_RENEW].include?(request['audience']) &&
                        %w[grantId operationNonce proofNonce registrationId credentialId].all? do |key|
                          request[key].is_a?(String) && JrcFlows::NativeClient::UUID.match?(request[key])
                        end
    raise Denied unless %w[expectedGeneration registrationRevision credentialRevision destinationRevision accountCredentialVersion
                           accountId].all? do |key|
      request[key].is_a?(Integer) && request[key].positive? && request[key]<=9_007_199_254_740_991
    end

    JrcFlowNativeInstallation.transaction do
      row = JrcFlowNativeInstallation.lock.find_by(callback_digest: Digest::SHA256.hexdigest(bearer))
      now = ApplicationRecord.connection.select_value('SELECT clock_timestamp()').to_time
      raise Denied unless row && !row.revoked_at && row.state != 'REVOKED' && row.operation_expires_at && row.operation_expires_at > now

      record = row.registration.reload
      expected = { 'grantId' => row.grant_id, 'operationNonce' => row.operation_nonce, 'expectedGeneration' => row.generation,
                   'registrationId' => record.broker_registration_id, 'registrationRevision' => record.broker_registration_revision,
                   'credentialId' => record.credential_id, 'credentialRevision' => record.credential_revision,
                   'destinationRevision' => record.destination_revision, 'accountCredentialVersion' => record.account_credential_version,
                   'accountId' => row.account_id, 'tupleDigest' => row.tuple_digest }
      raise Denied unless expected.all? { |key, value| request[key] == value }
      raise Denied if row.proof_nonce && row.proof_nonce != request['proofNonce']
      raise Denied unless request['audience'] == (row.state == 'PENDING' ? 'FLOW_INSTALLATION_CLAIM' : 'FLOW_INSTALLATION_RENEW')

      JrcFlows::NativeHostAuthority.new(account_id: row.account_id, user_id: row.created_by_id).administrator!
      JrcFlows::NativeHostAuthority.new(account_id: row.account_id, user_id: row.created_by_id).authorize!(
        record: record, inbox_ids: row.tuple.fetch('targets').map do |target|
          target.fetch('inboxId')
        end, scopes: ['flow:edit'], nonce: request['proofNonce']
      )
      row.update!(proof_nonce: request['proofNonce']) unless row.proof_nonce
      request.merge('authorized' => true)
    end
  rescue JrcFlows::NativeClient::Error, JrcFlows::NativeIntrospection::Denied, KeyError
    raise Denied
  end
end
