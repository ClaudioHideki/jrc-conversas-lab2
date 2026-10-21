# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::IntegrationsController < Api::V1::Accounts::JrcContactCenter::BaseController
  def health
    authorize_contact_center!(:control?)
    render json: base_payload.merge(JrcContactCenter::OperationalHealth.new(account: Current.account).call)
  end

  def capabilities
    authorize_contact_center!(:control?)
    adapter = JrcContactCenter::Providers::JrcPabxAdapter.new(account: Current.account)
    render json: base_payload.merge(
      provider: adapter.provider_key,
      capabilities: adapter.capabilities,
      legacy_telephony: {
        configured: TelephonyIntegration.exists?(account: Current.account),
        reused_as_jrc_pabx_contract: false
      },
      external_contracts: {
        jrc_pabx: 'pending_homologation',
        erp: 'pending_homologation'
      }
    )
  end
end
