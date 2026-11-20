# frozen_string_literal: true

# Module-local state for an existing Team. No shared membership or individual grant is changed.
class JrcContactCenter::TeamState < ApplicationRecord
  self.table_name = 'jrc_contact_center_team_states'

  include JrcContactCenter::AdministrativeAuditable

  belongs_to :account
  belongs_to :team
  attr_readonly :account_id, :team_id

  validates :team_id, uniqueness: true
  validates :active, inclusion: { in: [true, false] }
  validate :same_account

  def self.source_active?(account:, team_id:, preview: {})
    return preview.fetch(team_id) if preview.key?(team_id)

    !exists?(account: account, team_id: team_id, active: false)
  end

  private

  def same_account
    errors.add(:team, :invalid) unless team&.account_id == account_id
  end
end
