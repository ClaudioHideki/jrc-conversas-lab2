class JrcBackoffice::AuthorityOverview
  def initialize(account:, actor:, request_id:)
    @account = account
    @actor = actor
    @request_id = request_id
    @access = JrcBackoffice::ContractAccess.new(account: account, actor: actor)
  end

  def call(page: 1)
    request = @access.request(@request_id)
    version = current_version(request)
    rows = authorized_rows
    latest = version && rows.where(contract_version_id: version.id).order(revision: :desc).first
    payload = { version: version&.serializable_hash, signers: version&.signer_roster&.serializable_hash,
                current: latest && JrcBackoffice::AuthorityCase.new(proposal: latest, actor: @actor).call,
                can_propose: version.present? && writable?(version), approvals_enabled: @account.feature_enabled?('jrc_approvals') }
    payload.merge!(history_page(rows, page))
    @access.request(@request_id)
    payload
  end

  private

  # The sealed issuer/unit may differ from today's contract after a transfer.
  # Check each historical case before counting/paging it. No private snapshot
  # is serialized merely because the current Backoffice record is visible.
  def authorized_rows
    access = JrcBackoffice::AuthorityAccess.new(account: @account, actor: @actor)
    rows = scope.where(contract_id: @access.contracts.select(:id))
    ids = rows.includes(:signer_roster).find_each.filter_map do |record|
      access.read_case!(record)
      record.id
    rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
      nil
    end
    rows.where(id: ids)
  end

  def current_version(request)
    return unless request.contract_id

    contract = @access.contract!(request)
    JrcBackoffice::ContractVersions.new(account: @account, actor: @actor, request_id: request.id)
                                   .scope.where(contract_id: contract.id).order(number: :desc).first
  end

  def history_page(rows, page)
    total = rows.count
    pages = [(total / 10.0).ceil, 1].max
    current_page = page.to_s.to_i.clamp(1, pages)
    { data: rows.order(id: :desc).offset((current_page - 1) * 10).limit(10).map(&:serializable_hash),
      meta: { page: current_page, pages: pages, per_page: 10, total: total } }
  end

  def scope
    JrcBackoffice::AuthorityProposal.where(account_id: @account.id, backoffice_request_id: @request_id)
  end

  def writable?(version)
    JrcBackoffice::AuthorityAccess.new(account: @account, actor: @actor).authoring_version!(@request_id, version.id)
    true
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound, ArgumentError
    false
  end
end
