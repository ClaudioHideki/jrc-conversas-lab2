class JrcNico::Helpdesk::PolicyVersion < ApplicationRecord
  self.table_name = 'jrc_nico_helpdesk_policy_versions'
  belongs_to :account
  belongs_to :author, class_name: 'AccountUser'
  validates :number, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :account_id }
  validates :state, inclusion: { in: %w[draft published] }
  validates :enabled, inclusion: { in: [true, false] }
  validates :digest, format: { with: /\A[a-f0-9]{64}\z/ }
  validate :contract, :publication_integrity
  before_destroy { throw :abort }

  def published?
    state == 'published'
  end

  def enabled?
    self[:enabled] == true && !JrcNico::Helpdesk::PolicyControl.exists?(account_id: account_id, policy_version_id: id, halted: true)
  end

  def eligible?(ticket, member)
    published? && enabled? && member&.account_id == account_id && ticket.account_id == account_id && pilot_scope?(ticket, member)
  end

  private

  def pilot_scope?(ticket, member)
    definition.fetch('unit_ids').include?(ticket.unit_id) && definition.fetch('company_ids').include?(ticket.company_id) &&
      definition.fetch('operator_ids').include?(member.id)
  end

  def contract
    errors.add(:author, 'must belong to account') unless author&.account_id == account_id
    JrcNico::Helpdesk::Definition.validate!(definition)
    errors.add(:digest, 'does not match definition') unless digest == JrcNico::Helpdesk::Definition.digest(definition)
  rescue ArgumentError, KeyError => e
    errors.add(:definition, e.message)
  end

  def publication_integrity
    errors.add(:state, 'published versions are immutable') if state_in_database == 'published' && changed?
    errors.add(:published_at, 'required for published version') if published? && published_at.nil?
  end
end
