# frozen_string_literal: true

# Operational metadata for the existing Team. It is not a permission or distribution source.
class JrcContactCenter::TeamSupervision < ApplicationRecord
  self.table_name = 'jrc_contact_center_team_supervisions'

  include JrcContactCenter::AdministrativeAuditable
  KINDS = %w[primary additional].freeze

  belongs_to :account
  belongs_to :team, inverse_of: :jrc_contact_center_supervisions
  belongs_to :account_user, inverse_of: :jrc_contact_center_supervisions
  attr_readonly :account_id, :team_id, :account_user_id

  validates :kind, inclusion: { in: KINDS }
  validates :account_user_id, uniqueness: { scope: :team_id }
  validates :team_id, uniqueness: { conditions: -> { where(kind: 'primary') } }, if: -> { kind == 'primary' }
  validate :same_account

  private

  def same_account
    errors.add(:team, :invalid) unless team&.account_id == account_id
    errors.add(:account_user, :invalid) unless account_user&.account_id == account_id
  end
end
