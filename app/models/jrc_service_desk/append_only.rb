# frozen_string_literal: true

# Append-only at the domain/ActiveRecord boundary, not a claim about privileged SQL.
# No update/delete command is exposed. Database FKs still protect referential scope.
module JrcServiceDesk::AppendOnly
  def readonly?
    super || persisted?
  end

  def delete
    raise ActiveRecord::ReadOnlyRecord, 'Service Desk history is append-only' if persisted?

    super
  end
end
