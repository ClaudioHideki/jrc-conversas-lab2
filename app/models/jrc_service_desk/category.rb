# frozen_string_literal: true

class JrcServiceDesk::Category < JrcServiceDesk::NamedUnitRecord
  has_many :tickets, class_name: 'JrcServiceDesk::Ticket', dependent: :restrict_with_error
end
