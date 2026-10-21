# == Schema Information
#
# Table name: jrc_campaign_sanitized_entries
#
#  id                :bigint           not null, primary key
#  email             :string
#  metadata          :jsonb            not null
#  name              :string
#  normalized_email  :string
#  normalized_phone  :string
#  phone_number      :string
#  reason            :string
#  status            :string           default("valid"), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  sanitized_list_id :bigint           not null
#
# Indexes
#
#  idx_jrc_sanitized_entries_list_email                       (sanitized_list_id,normalized_email)
#  idx_on_sanitized_list_id_normalized_phone_b94ac446e9       (sanitized_list_id,normalized_phone)
#  idx_on_sanitized_list_id_status_b19511a848                 (sanitized_list_id,status)
#  index_jrc_campaign_sanitized_entries_on_sanitized_list_id  (sanitized_list_id)
#
# Foreign Keys
#
#  fk_rails_...  (sanitized_list_id => jrc_campaign_sanitized_lists.id)
#
class JrcCampaigns::SanitizedEntry < ApplicationRecord
  self.table_name = 'jrc_campaign_sanitized_entries'

  STATUSES = %w[valid invalid duplicate blacklisted].freeze

  belongs_to :sanitized_list, class_name: 'JrcCampaigns::SanitizedList'

  validates :status, inclusion: { in: STATUSES }
end
