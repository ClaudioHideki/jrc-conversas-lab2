class JrcFlows::NativeOwnershipBrokerProof
  module ClientMethod
    def ownership_reopen_proof(id, input)
      request(:post, "/native-cutovers/#{identifier!(id)}/reopen-proof", body: input)
    end
  end

  def self.observe!(registration, request)
    token=JrcFlows::NativeCredentialStore.for_application.decrypt(account_id: registration.account_id, record_id: registration.id,
                                                                  revision: registration.revision, purpose: 'OUTBOUND',
                                                                  ciphertext: registration.encrypted_outbound_credential)
    client=JrcFlows::NativeClient.new(origin: registration.broker_origin, credential: token)
    client.extend(ClientMethod)
    input={ credentialId: registration.credential_id, credentialRevision: registration.credential_revision,
            registrationId: registration.broker_registration_id, registrationRevision: registration.broker_registration_revision,
            integrationId: request['integrationId'], accountId: registration.account_id, inboxId: request['inboxId'],
            destinationRevision: registration.destination_revision, accountCredentialVersion: registration.account_credential_version,
            cutoverRevision: request['cutoverRevision'], expectedCurrentOwnerRevision: request.fetch('expectedCurrentOwnerRevision'),
            nonce: request['nonce'] }
    client.ownership_reopen_proof(request['cutoverId'], input)
  end
end
