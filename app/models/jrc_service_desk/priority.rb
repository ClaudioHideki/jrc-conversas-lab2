# frozen_string_literal: true

class JrcServiceDesk::Priority < JrcServiceDesk::NamedUnitRecord
  has_many :tickets, class_name: 'JrcServiceDesk::Ticket', dependent: :restrict_with_error

  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
