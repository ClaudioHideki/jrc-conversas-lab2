# frozen_string_literal: true

# Read the native tickets through the same query/policy as the Service Desk list.
# The immutable private origin selects a recording; it never grants destination access.
class JrcContactCenter::RecordingTicketList
  def initialize(account:, member:, page: 1)
    raise Pundit::NotAuthorizedError unless member && member.account_id == account.id

    @account = account
    @member = member
    @page = JrcServiceDesk::Input.id(page)
    raise ArgumentError unless @page <= 1_000_000
  end

  def call(recording_id)
    source = JrcContactCenter::QualityReviewSource.new(account: @account, member: @member, action: :recordings_listen)
    source.with_record(recording_id) do |record, call|
      collection = authorized_collection(record, call)
      context = { account: @account, account_user: @member, user: @member.user }
      presenter = JrcServiceDesk::Presenter.new(user_context: context, read_only: true)
      items = collection.fetch(:items).map do |ticket|
        presenter.ticket(ticket).slice(:id, :number, :title, :status, :status_phase)
      end
      meta = collection.fetch(:meta)
      { contract_version: 1, account_id: @account.id.to_s, user_id: @member.user_id.to_s,
        recording_id: record.id.to_s, call_session_id: call.id.to_s, call_id: call.external_session_id,
        items: items, meta: meta.merge(pages: (meta.fetch(:total) / 20.0).ceil) }
    end
  end

  private

  def authorized_collection(record, call)
    origin = { recording_origin: { schema_version: 1, recording_id: record.id, call_session_id: call.id, call_id: call.external_session_id } }
    events = JrcServiceDesk::TicketEvent.where(account_id: @account.id, event_type: 'creation_context_recorded')
                                      .where('data @> ?::jsonb', origin.to_json).select(:ticket_id)
    selected = JrcServiceDesk::Ticket.where(account_id: @account.id, id: events)
    context = { account: @account, account_user: @member, user: @member.user }
    JrcServiceDesk::TicketQuery.new(user_context: context, scope: selected,
                                    parameters: { page: @page, per_page: 20, sort: 'created_at_desc' }).collection
  end
end
