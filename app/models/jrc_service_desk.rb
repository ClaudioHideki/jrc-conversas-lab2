# frozen_string_literal: true

# Separate domain: this is not jrcService (Cockpit).
module JrcServiceDesk
  FEATURE_FLAG = 'jrc_service_desk'

  def self.table_name_prefix
    'jrc_service_desk_'
  end
end
