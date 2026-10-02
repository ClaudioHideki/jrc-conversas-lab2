require 'digest'
require 'json'

# Explicit, reviewable operational backfill. No name matching and no operator IDs.
class JrcCustomers::OperationsBackfill
  MODELS = [JrcServiceDesk::Ticket, JrcProjects::Project].freeze
  class StalePlan < ArgumentError; end

  def initialize(account:)
    @account = account
  end

  def plan
    report = { account_id: @account.id, pending: [], conflicts: [], unlinked_without_evidence: {} }
    MODELS.each do |model|
      missing = 0
      model.where(account_id: @account.id, company_id: nil).order(:id).find_each do |record|
        begin
          target = JrcCustomers::CompanyLinkDecision.resolve(candidates: record.master_company_candidates)
          if target.nil?
            missing += 1 # Internal projects / provisional requesters are legitimate.
            next
          end
          JrcCustomers::Company.where(account_id: @account.id).find(target)
          report[:pending] << { table: model.table_name, id: record.id, company_id: target,
                                lock_version: record.lock_version, evidence: record.master_company_candidates.uniq.sort }
        rescue JrcCustomers::CompanyLinkDecision::Conflict, ActiveRecord::RecordNotFound => error
          report[:conflicts] << { table: model.table_name, id: record.id, error: error.message }
        end
      end
      report[:unlinked_without_evidence][model.table_name] = missing
    end
    report[:digest] = Digest::SHA256.hexdigest(JSON.generate(report))
    report
  end

  def apply!(reviewed_digest:)
    raise StalePlan, 'Supply the digest of the reviewed dry-run plan' unless reviewed_digest.to_s.match?(/\A[0-9a-f]{64}\z/)

    @account.with_lock do
      # Maintenance operation: account -> contact -> ticket/project lock order.
      # Source identities must not change while their evidence is being applied.
      @account.contacts.order(:id).lock.load
      report = plan
      raise StalePlan, 'Plan changed; generate and review a new dry run' unless report[:digest] == reviewed_digest
      raise StalePlan, 'Resolve conflicting evidence before applying' if report[:conflicts].any?

      report[:pending].each do |row|
        model = MODELS.find { |candidate| candidate.table_name == row[:table] }
        record = model.where(account_id: @account.id).lock.find(row[:id])
        fresh_target = JrcCustomers::CompanyLinkDecision.resolve(candidates: record.master_company_candidates)
        unless record.company_id.nil? && record.lock_version == row[:lock_version] && fresh_target == row[:company_id]
          raise StalePlan, 'Operational source changed while applying; no rows committed'
        end
        changed = model.where(account_id: @account.id, id: record.id, company_id: nil, lock_version: row[:lock_version])
                       .update_all(company_id: row[:company_id], lock_version: row[:lock_version] + 1)
        raise StalePlan, 'Concurrent update; no rows committed' unless changed == 1
        # Existing native logs remain untouched. Administrative linking is audited separately.
        JrcCustomers::Audit.record!(account: @account, actor: nil, resource: record,
                                   event_type: 'customer_operations_backfilled', to_value: { company_id: row[:company_id] },
                                   metadata: { reviewed_digest: reviewed_digest, evidence: row[:evidence] })
      end
      report.merge(applied: true)
    end
  end
end
