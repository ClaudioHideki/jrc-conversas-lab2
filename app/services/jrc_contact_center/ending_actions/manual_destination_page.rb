# frozen_string_literal: true

# Explicit read of original-agent action eligibility. Audit/configure authority
# never impersonates that agent; the independent write command checks again.
class JrcContactCenter::EndingActions::ManualDestinationPage
  def initialize(account:, member:, qualification_id:, page: 1)
    @account = account
    @member = member
    @qualification_id = qualification_id
    @page = JrcServiceDesk::Input.version(page).clamp(1, 1_000_000)
  rescue ArgumentError
    raise JrcContactCenter::OperationError, 'invalid_ending_history_page'
  end

  def call
    JrcContactCenter::EndingActions::HistoryContext.new(
      account: @account, member: @member, qualification_id: @qualification_id
    ).call do |member, qualification|
      origins = JrcContactCenter::EndingActionOrigin.where(account: @account, source_qualification_id: qualification.id,
                                                         actor_account_user_id: member.id, actor_user_id: member.user_id).order(:id)
      items = origins.flat_map do |origin|
        JrcContactCenter::EndingActions::ManualDestinationPreview.new(account: @account, member: member, origin: origin).call
      end
      ordered = items.sort_by { |row| [row.fetch('origin_id').to_i, row.fetch('rule_code'), row.fetch('destination_kind')] }
      { qualification_id: qualification.id.to_s, items: ordered.slice((@page - 1) * 20, 20) || [],
        meta: { page: @page, per_page: 20, total: items.length, pages: (items.length / 20.0).ceil } }
    end
  end
end
