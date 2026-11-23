# frozen_string_literal: true

# Captured only by the owned database guards, never by a
# settings/controller grant or an inferred mapping of a historical call.
class JrcContactCenter::EndingActionQueueScope < JrcContactCenter::ApplicationRecord
  include JrcApprovals::Immutable

  belongs_to :queue, class_name: 'JrcContactCenter::Queue', optional: true
  self.filter_attributes += [:payload]
end
