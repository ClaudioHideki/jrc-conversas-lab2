# A scoped operational view of persisted facts, with no provider I/O. Historical
# issuer/unit coverage is checked before counts or pagination expose a row.
class JrcBackoffice::Signatures::History
  def initialize(account:, actor:, request_id:)
    @account = account
    @actor = actor
    @request_id = request_id
    @access = JrcBackoffice::ContractAccess.new(account: account, actor: actor)
  end

  def call(page: 1)
    request = @access.request(@request_id)
    contract = request.contract_id && @access.contract!(request)
    rows = authorized_rows
    selected, meta = paginate(rows.order(id: :desc), page, 10)
    data = selected.includes(:contract_version).map { |delivery| summary(delivery) }
    payload = { data: data, meta: meta, workflow_version: request.workflow_version,
                signature_required: request.stage_applicable?('contract'),
                signature_requirement_satisfied: JrcBackoffice::SignatureRelease.satisfied?(request), contract: contract && {
                  id: contract.id, number: contract.contract_number, signature_status: contract.signature_status,
                  signature_verified: JrcBackoffice::SignatureRelease.verified?(contract)
                } }
    data.each { |row| authorize!(rows.find(row.fetch('id'))) }
    @access.request(@request_id)
    payload
  end

  def show(id, page: 1)
    delivery = authorized_rows.find(id)
    rows, meta = paginate(delivery.events.order(id: :desc), page, 20)
    result = { delivery: summary(delivery), data: rows.map { |event| event.slice('id', 'kind', 'created_at') }, meta: meta }
    authorize!(delivery)
    @access.request(@request_id)
    result
  end

  private

  def scope
    JrcBackoffice::Signatures::Admissions.new(account: @account, actor: @actor, request_id: @request_id).scope
  end

  def authorized_rows
    rows = scope
    ids = rows.includes(authority_proposal: :signer_roster).find_each.filter_map do |record|
      authorize!(record)
      record.id
    rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
      nil
    end
    rows.where(id: ids)
  end

  def authorize!(delivery)
    JrcBackoffice::AuthorityAccess.new(account: @account, actor: @actor).read_case!(delivery.authority_proposal)
  end

  def summary(delivery)
    source = delivery.snapshot
    delivery.serializable_hash.merge('version_number' => delivery.contract_version.number,
                                     'connection_revision' => source.fetch('connection_revision'),
                                     'last_event_at' => delivery.events.order(id: :desc).pick(:created_at))
  end

  def paginate(rows, page, size)
    total = rows.count
    pages = [(total / size.to_f).ceil, 1].max
    current = page.to_s.to_i.clamp(1, pages)
    [rows.offset((current - 1) * size).limit(size), { page: current, pages: pages, per_page: size, total: total }]
  end
end
