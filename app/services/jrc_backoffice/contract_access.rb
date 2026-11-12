# Shared by interactive actions and jobs; ownership and corporate restrictions
# are the native Backoffice restrictions, never a caller-supplied account/unit.
class JrcBackoffice::ContractAccess
  attr_reader :account, :actor

  def initialize(account:, actor:)
    @account = account
    @actor = actor
  end

  def request(id)
    requests.find(id)
  end

  def requests
    member = membership!
    rows = account.jrc_crm_backoffice_requests
    rows = rows.where(owner_id: actor.id) unless member.administrator?
    JrcCrm::OrganizationalVisibility.new(account: account, user: actor, relation: rows).call
  end

  def membership!
    raise Pundit::NotAuthorizedError unless actor.is_a?(User)

    account.reload
    actor.reload
    member = AccountUser.find_by(account_id: account.id, user_id: actor.id)
    raise Pundit::NotAuthorizedError unless account.active? && account.feature_enabled?('jrc_crm') && authorized_member?(member)

    member
  end

  def writable!(record)
    current = request(record.id)
    raise ArgumentError, 'Reabra uma solicitação operacional antes de alterar o contrato.' unless writable?(current)

    current
  end

  def writable?(record)
    !record.status.in?(%w[completed canceled rejected]) && !record.order_approval?
  end

  def contract!(record)
    contract = contracts.find(record.contract_id)
    raise ActiveRecord::RecordNotFound unless contract.sales_order_id == record.sales_order_id

    contract
  end

  def contracts
    JrcCrm::OrganizationalVisibility.new(account: account, user: actor, relation: account.jrc_crm_contracts).call
  end

  private

  def authorized_member?(member)
    member && actor.active_for_authentication? && member.permissions.include?('jrc_crm')
  end
end
