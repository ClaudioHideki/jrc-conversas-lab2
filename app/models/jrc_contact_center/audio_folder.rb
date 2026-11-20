# frozen_string_literal: true

# Institutional organization only. Never contains call recordings or shared Help Center folders.
class JrcContactCenter::AudioFolder < JrcContactCenter::ApplicationRecord
  include JrcContactCenter::AdministrativeAuditable

  belongs_to :unit, class_name: 'JrcContactCenter::Unit'
  belongs_to :parent, class_name: 'JrcContactCenter::AudioFolder', optional: true
  has_many :children, class_name: 'JrcContactCenter::AudioFolder', foreign_key: :parent_id, inverse_of: :parent, dependent: :restrict_with_error
  attr_readonly :account_id, :unit_id

  validates :name, presence: true, length: { maximum: 120 }, uniqueness: { scope: %i[account_id unit_id parent_id], case_sensitive: false }
  validates :description, length: { maximum: 1000 }
  validate :native_unit_and_parent
  validate :acyclic_hierarchy
  before_validation { self.name = name&.strip }

  private

  def native_unit_and_parent
    errors.add(:unit, :invalid) unless unit&.account_id == account_id
    return unless parent

    errors.add(:parent, :invalid) unless parent.account_id == account_id && parent.unit_id == unit_id
  end

  def acyclic_hierarchy
    return errors.add(:parent, :invalid) if parent.equal?(self)

    seen = [id].compact
    cursor = parent
    while cursor
      if seen.include?(cursor.id)
        errors.add(:parent, :invalid)
        break
      end
      seen << cursor.id
      cursor = cursor.parent_id ? self.class.find_by(account_id: account_id, unit_id: unit_id, id: cursor.parent_id) : nil
    end
  end
end
