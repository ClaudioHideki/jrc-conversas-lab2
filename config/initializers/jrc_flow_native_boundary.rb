require Rails.root.join('app/services/jrc_flows/native_body_limit')
# Route-scoped input bound before Rails parses request parameters.
Rails.application.config.middleware.insert_before 0, JrcFlows::NativeBodyLimit
Rails.application.config.filter_parameters += %i[nativeCredential callbackCredential transferNonce installationCallbackCredential
                                                 nativeCallbackCredential native_credential callback_credential transfer_nonce encrypted_grant
                                                 encrypted_callback encrypted_transfer_nonce encrypted_renew_callback encrypted_revoke_bearer]
