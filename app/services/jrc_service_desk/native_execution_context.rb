# frozen_string_literal: true

module JrcServiceDesk::NativeExecutionContext
  FIELDS = %i[user account account_user executed_by contact inbox].freeze

  def self.with(context)
    previous = FIELDS.index_with { |field| Current.public_send(field) }
    FIELDS.each { |field| Current.public_send("#{field}=", context[field]) }
    yield
  ensure
    previous&.each { |field, value| Current.public_send("#{field}=", value) }
  end
end
