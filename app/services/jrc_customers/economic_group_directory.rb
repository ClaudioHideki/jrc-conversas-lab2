class JrcCustomers::EconomicGroupDirectory
  def initialize(account:, actor:)
    @account = account
    @actor = actor
  end

  def scope
    JrcCustomers::ContactDirectory.new(account: @account, actor: @actor).authorize!
    groups = JrcCustomers::EconomicGroup.where(account_id: @account.id)
    occupied = @account.master_companies.where.not(economic_group: nil).select(:economic_group)
    groups.where(name: companies.select(:economic_group)).or(groups.where.not(name: occupied))
  end

  def companies
    JrcCrm::CorporateCoverage.new(account: @account, user: @actor).companies(@account.master_companies)
  end

  def members(group)
    companies.where(economic_group: group.name)
  end

  def complete_coverage?(group)
    return true unless group.persisted?

    !group.companies.where.not(id: companies.reselect(:id)).exists?
  end
end
