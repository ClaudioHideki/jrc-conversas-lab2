# Read-only contract dates from the already authorized Customer360 relation.
class JrcCustomers::ContractRenewalContext
  def initialize(contracts:, account:)
    @contracts = contracts
    @account = account
  end

  def summary
    { contracts_active: @contracts.count, contracts_mrr_cents: @contracts.sum(:monthly_cents), contract_renewal: call }
  end

  def call
    today = Time.current.in_time_zone(Time.find_zone(@account.reporting_timezone) || Time.zone).to_date
    upcoming = @contracts.where('ends_on >= ?', today).order(:ends_on, :id).first
    notice_on = upcoming && (upcoming.ends_on - upcoming.renewal_notice_days)
    { next: upcoming && { id: upcoming.id, contract_number: upcoming.contract_number, ends_on: upcoming.ends_on.iso8601,
                          renewal_notice_days: upcoming.renewal_notice_days, notice_on: notice_on.iso8601,
                          within_notice_window: today >= notice_on },
      overdue: @contracts.where('ends_on < ?', today).count, undated: @contracts.where(ends_on: nil).count }
  end
end
