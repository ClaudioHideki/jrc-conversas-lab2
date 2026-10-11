# == Schema Information
#
# Table name: jrc_nico_inferences
#
#  id              :bigint           not null, primary key
#  reserved_tokens :integer          default(0), not null
#  status          :string           default("running"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  user_id         :bigint           not null
#
# Indexes
#
#  index_jrc_nico_inferences_on_account_id                 (account_id)
#  index_jrc_nico_inferences_on_account_id_and_created_at  (account_id,created_at)
#  index_jrc_nico_inferences_on_user_id                    (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
class JrcNico::Inference < ApplicationRecord
  self.table_name = 'jrc_nico_inferences'
  belongs_to :account
  belongs_to :user

  validates :status, inclusion: { in: %w[running completed unknown failed] }
  validates :reserved_tokens, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
