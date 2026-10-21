# frozen_string_literal: true

class JrcContactCenter::Providers::JrcPabxAdapter < JrcContactCenter::Providers::BaseAdapter
  def provider_key
    'jrc_pabx'
  end

  def capabilities
    super.merge(
      'provider_adapter' => 'available',
      'external_api' => 'pending_contract',
      'event_schema' => 'proposed'
    )
  end
end
