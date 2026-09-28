# frozen_string_literal: true

class JrcServiceDesk::NamedUnitRecord < JrcServiceDesk::UnitRecord
  self.abstract_class = true

  validates :code, presence: true, length: { maximum: 80 }, uniqueness: { scope: %i[account_id unit_id] }
  validates :name, presence: true, length: { maximum: 255 }
  validates :active, inclusion: { in: [true, false] }
end
