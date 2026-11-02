class JrcBackoffice::SignerRosters
  class Changed < StandardError; end
  INPUT_FIELDS = %w[idempotency_key expected_revision expected_source_digest customer_mode issuer_mode signers change_reason].freeze

  def initialize(account:, actor:, request_id:)
    @access = JrcBackoffice::ContractAccess.new(account: account, actor: actor)
    @request_id = request_id
    @directory = JrcCustomers::ContactDirectory.new(account: account, actor: actor)
  end

  def scope
    request = @access.request(@request_id)
    JrcBackoffice::SignerRoster.where(account_id: @access.account.id, backoffice_request_id: request.id,
                                      contract_id: @access.contracts.select(:id))
  end

  def current
    request = @access.request(@request_id)
    contract = @access.contract!(request)
    scope.where(contract_id: contract.id).order(revision: :desc).first
  end

  def overview(page: 1)
    request = @access.request(@request_id)
    contract = request.contract_id && @access.contract!(request)
    rows = scope.order(id: :desc)
    current = contract && rows.where(contract_id: contract.id).order(revision: :desc).first
    payload = history_page(rows, page, current).merge(current: current&.serializable_hash, contract: contract_summary(contract),
                                                      writable: contract.present? && editable_context?(request, contract),
                                                      signing_authority_verified: false)
    @access.request(@request_id)
    payload
  end

  def create!(**attributes)
    @access.membership!
    @directory.authorize!
    input = normalize_input(attributes.stringify_keys.slice(*INPUT_FIELDS))
    locked_context { |request, contract| persist!(request, contract, input) }
  end

  private

  def history_page(rows, page, current)
    total = rows.count
    pages = [(total / 10.0).ceil, 1].max
    current_page = page.to_s.to_i.clamp(1, pages)
    selected = rows.includes(:created_by).offset((current_page - 1) * 10).limit(10).to_a
    { data: history_rows(selected, current&.id), meta: { page: current_page, pages: pages, total: total, per_page: 10 } }
  end

  def history_rows(selected, current_id)
    raise Changed unless scope.where(id: selected.map(&:id)).count == selected.length

    selected.map { |row| row.serializable_hash.merge('created_by_name' => row.created_by.name, 'current' => row.id == current_id) }
  end

  def contract_summary(contract)
    return unless contract

    { id: contract.id, number: contract.contract_number, source_digest: JrcBackoffice::ContractSnapshot.digest(contract) }
  end

  def editable_context?(request, contract)
    return false unless @access.writable?(request) && !contract.signature_status.in?(%w[sent signed])

    @directory.authorize!
    true
  rescue Pundit::NotAuthorizedError
    false
  end

  def locked_context
    @access.account.with_lock('FOR NO KEY UPDATE', requires_new: true) do
      request = @access.writable!(@access.request(@request_id))
      request.sales_order.with_lock('FOR NO KEY UPDATE') do
        request.with_lock('FOR NO KEY UPDATE') do
          contract = @access.contract!(request)
          contract.with_lock('FOR NO KEY UPDATE') { yield(request, contract) }
        end
      end
    end
  end

  def normalize_input(input)
    JrcApprovals::Ledger.key!(input['idempotency_key'])
    reason = input['change_reason']
    raise ArgumentError, 'Informe o motivo da revisão dos assinantes.' unless reason.is_a?(String) && reason.strip.length.between?(1, 2000)

    modes = { 'customer' => input['customer_mode'], 'issuer' => input['issuer_mode'] }
    rows = JrcBackoffice::SignerSelection.call(JrcServiceDesk::CanonicalJson.normalize(input['signers']), modes)
    input.merge('expected_revision' => Integer(input['expected_revision'].to_s, 10), 'signers' => rows, 'change_reason' => reason.strip)
  end

  def persist!(request, contract, input)
    fingerprint = input.merge('account_id' => @access.account.id, 'contract_id' => contract.id,
                              'backoffice_request_id' => request.id, 'actor_id' => @access.actor.id)
    input['input_digest'] = JrcApprovals::Ledger.digest(fingerprint)
    existing = replayed!(input)
    return existing if existing

    editable!(contract)
    input['revision'] = next_revision!(contract, input)
    snapshot = capture_source(request, contract, input)
    @directory.authorize!
    @access.writable!(request)
    check_source!(contract, input)
    record = create_record!(request, contract, snapshot, input)
    audit!(request, record)
    record
  end

  def replayed!(input)
    record = scope.find_by(idempotency_key: input['idempotency_key'])
    return unless record

    raise Changed unless record.input_digest == input['input_digest']

    record
  end

  def next_revision!(contract, input)
    revision = scope.where(contract_id: contract.id).maximum(:revision).to_i
    raise Changed unless input['expected_revision'] == revision

    check_source!(contract, input)
    revision + 1
  end

  def check_source!(contract, input)
    raise Changed unless input['expected_source_digest'] == JrcBackoffice::ContractSnapshot.digest(contract.reload)
  end

  def capture_source(request, contract, input)
    source = JrcBackoffice::SignerRosterSource.new(account: @access.account, actor: @access.actor, request: request, contract: contract)
    source.capture(selections: input['signers'], customer_mode: input['customer_mode'], issuer_mode: input['issuer_mode'])
  end

  def create_record!(request, contract, snapshot, input)
    JrcBackoffice::SignerRoster.create!(
      account: @access.account, contract: contract, backoffice_request: request, created_by: @access.actor,
      revision: input['revision'], customer_mode: input['customer_mode'], issuer_mode: input['issuer_mode'],
      idempotency_key: input['idempotency_key'], change_reason: input['change_reason'],
      source_snapshot: JrcServiceDesk::CanonicalJson.dump(snapshot),
      source_digest: JrcBackoffice::SignerRosterSource.digest(snapshot), input_digest: input['input_digest']
    )
  end

  def editable!(contract)
    return unless contract.signature_status.in?(%w[sent signed])

    raise ArgumentError, 'Preserve os assinantes do contrato enviado ou assinado; use o fluxo autorizado de revisão.'
  end

  def audit!(request, record)
    JrcCrm::AuditEvent.create!(account: @access.account, actor_type: 'User', actor_id: @access.actor.id,
                               event_type: 'backoffice_signer_roster_created', resource_type: request.class.name, resource_id: request.id,
                               from_value: {}, to_value: { signer_roster_id: record.id, revision: record.revision },
                               metadata: { source: 'backoffice_signers', signing_authority_verified: false, external_delivery: false })
  end
end
