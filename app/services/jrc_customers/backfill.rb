require 'digest'
require 'json'

class JrcCustomers::Backfill
  class ReviewRequired < ArgumentError; end
  COMPANY_TABLES = %w[contacts jrc_crm_organizations jrc_crm_leads jrc_crm_deals jrc_crm_activities jrc_service_desk_tickets jrc_projects_projects].freeze
  def initialize(account:, mappings: {})
    @account = account
    @mappings = mappings.stringify_keys
  end

  def run(apply: false)
    report = { account_id: @account.id, mode: apply ? 'apply' : 'dry_run', organizations: [], contacts_linked: [], conflicts: invalid_links }
    return with_digest(report.merge(blocked: true)) if report[:conflicts].any?

    @account.jrc_crm_organizations.order(:id).find_each do |organization|
      mapper = JrcCustomers::LegacyCompanyMapper.new(account: @account, organization: organization,
                                                    target_company_id: @mappings[organization.id.to_s])
      begin
        decision = mapper.plan
        decision[:company_id] = mapper.apply!.id if apply
        report[:organizations] << decision
      rescue JrcCustomers::LegacyCompanyMapper::Conflict, ActiveRecord::ActiveRecordError => e
        report[:conflicts] << { organization_id: organization.id, error: e.message }
      end
    end
    link_unambiguous_contacts(report, apply: apply)
    link_unambiguous_leads(report, apply: apply)
    link_unambiguous_crm_records(report, apply: apply)
    report[:remaining_unmapped_organizations] = @account.jrc_crm_organizations.where(company_id: nil).count
    with_digest(report)
  end

  # Console writes are explicit, reviewed and all-or-nothing. Run in maintenance
  # mode: legacy module writers do not all take an account-level lock.
  def apply_reviewed!(reviewed_digest:)
    raise ReviewRequired, 'Supply REVIEWED_SHA256 from the CRM dry run' unless reviewed_digest.to_s.match?(/\A[0-9a-f]{64}\z/)

    @account.with_lock do
      @account.contacts.order(:id).lock.load
      report = run
      raise ReviewRequired, 'Dry-run changed; review a fresh plan' unless report[:digest] == reviewed_digest
      raise ReviewRequired, 'Resolve conflicts before applying' if report[:conflicts].any?

      applied = run(apply: true)
      raise ReviewRequired, 'Application conflicted; all changes rolled back' if applied[:conflicts].any?

      applied.merge(reviewed_digest: reviewed_digest, next_review: run)
    end
  end

  def invalid_links
    links = COMPANY_TABLES.map { |table| [table, 'company_id', 'companies'] }
    links += %w[jrc_crm_leads jrc_crm_deals jrc_crm_activities].map { |table| [table, 'contact_id', 'contacts'] }
    links += %w[jrc_crm_deals jrc_crm_activities].map { |table| [table, 'organization_id', 'jrc_crm_organizations'] }
    links += %w[jrc_projects_projects jrc_crm_sales_orders jrc_crm_contracts jrc_crm_invoices jrc_crm_backoffice_requests].map { |table| [table, 'contact_id', 'contacts'] }
    links += [['jrc_service_desk_tickets', 'requester_id', 'contacts'],
              ['jrc_operations_links', 'ticket_id', 'jrc_service_desk_tickets'],
              ['jrc_operations_links', 'project_id', 'jrc_projects_projects'],
              ['jrc_operations_links', 'crm_deal_id', 'jrc_crm_deals'],
              ['jrc_operations_links', 'conversation_id', 'conversations']]
    links += [['companies', 'parent_company_id', 'companies'], ['contact_points', 'contact_id', 'contacts'],
              ['company_addresses', 'company_id', 'companies']]
    findings = links.flat_map do |table, column, target|
      sql = ActiveRecord::Base.sanitize_sql_array([
        "SELECT source.id, source.#{column} FROM #{table} source LEFT JOIN #{target} target ON target.id = source.#{column} " \
        "WHERE source.account_id = ? AND source.#{column} IS NOT NULL AND (target.id IS NULL OR target.account_id <> source.account_id)",
        @account.id
      ])
      ActiveRecord::Base.connection.select_all(sql).map do |row|
        row.merge('table' => table, 'column' => column, 'error' => 'invalid_tenant_link')
      end
    end
    sql = ActiveRecord::Base.sanitize_sql_array([
      'SELECT links.id, links.contact_id, links.deal_id FROM jrc_crm_deal_contacts links ' \
      'JOIN jrc_crm_deals deals ON deals.id = links.deal_id LEFT JOIN contacts contacts ON contacts.id = links.contact_id ' \
      'WHERE deals.account_id = ? AND (contacts.id IS NULL OR contacts.account_id <> deals.account_id)', @account.id
    ])
    findings += ActiveRecord::Base.connection.select_all(sql).map { |row| row.merge('table' => 'jrc_crm_deal_contacts', 'error' => 'invalid_tenant_link') }
    recipients = JrcCampaigns::Recipient.joins(:campaign).where(jrc_campaigns: { account_id: @account.id }).where.not(contact_id: nil)
    recipients.where.not(contact_id: @account.contacts.select(:id)).pluck(:id, :contact_id).each do |id, contact_id|
      findings << { table: 'jrc_campaign_recipients', id: id, contact_id: contact_id, error: 'invalid_tenant_link' }
    end
    findings
  end

  private

  def with_digest(report)
    report.merge(digest: Digest::SHA256.hexdigest(JSON.generate(report)))
  end


  def link_unambiguous_crm_records(report, apply:)
    report[:crm_links] = []
    [@account.jrc_crm_deals, @account.jrc_crm_activities].each do |scope|
      scope.where(company_id: nil).find_each do |record|
        organization = record.organization_id.present? ? @account.jrc_crm_organizations.find_by(id: record.organization_id) : nil
        candidates = [record.contact&.company_id, organization&.company_id]
        candidates += [record.deal&.company_id, record.lead&.company_id] if record.is_a?(JrcCrm::Activity)
        begin
          target = JrcCustomers::CompanyLinkDecision.resolve(candidates: candidates)
          next unless target

          @account.master_companies.find(target)
          if apply
            record.with_lock do
              if record.company_id.nil?
                record.update_columns(company_id: target)
                JrcCustomers::Audit.record!(account: @account, actor: nil, resource: record,
                  event_type: 'customer_operations_backfilled', to_value: { company_id: target },
                  metadata: { source: 'crm_exact_reference_backfill' })
              end
            end
          end
          report[:crm_links] << { table: record.class.table_name, id: record.id, company_id: target, applied: apply }
        rescue JrcCustomers::CompanyLinkDecision::Conflict => error
          report[:conflicts] << { table: record.class.table_name, id: record.id, error: error.message }
        end
      end
    end
  end

  def link_unambiguous_leads(report, apply:)
    report[:leads_linked] = []
    @account.jrc_crm_leads.where(company_id: nil).where.not(contact_id: nil).find_each do |lead|
      contact = @account.contacts.find_by(id: lead.contact_id)
      next unless contact&.company_id

      if apply
        lead.with_lock do
          contact.reload
          if lead.company_id.nil? && contact.company_id
            lead.update_columns(company_id: contact.company_id)
            JrcCustomers::Audit.record!(account: @account, actor: nil, resource: lead,
              event_type: 'customer_operations_backfilled', to_value: { company_id: contact.company_id },
              metadata: { source: 'crm_contact_exact_reference', contact_id: contact.id })
          end
        end
      end
      report[:leads_linked] << { lead_id: lead.id, contact_id: contact.id, company_id: contact.company_id, applied: apply }
    end
  end

  def link_unambiguous_contacts(report, apply:)
    # Never infer a company from a display name. Only exact existing CRM links.
    @account.contacts.where(company_id: nil).find_each do |contact|
      deals = @account.jrc_crm_deals.where(contact_id: contact.id)
      joins = JrcCrm::DealContact.where(contact_id: contact.id).select(:deal_id)
      deals = deals.or(@account.jrc_crm_deals.where(id: joins))
      ids = deals.where.not(company_id: nil).distinct.pluck(:company_id)
      ids += @account.jrc_crm_leads.where(contact_id: contact.id).where.not(company_id: nil).distinct.pluck(:company_id)
      ids.uniq!
      next if ids.empty?
      if ids.length > 1
        report[:conflicts] << { contact_id: contact.id, error: 'multiple_companies_in_history', company_ids: ids }
        next
      end
      @account.master_companies.find(ids.first)
      if apply
        contact.with_lock do
          if contact.company_id.nil?
            contact.update!(company_id: ids.first)
            JrcCustomers::Audit.record!(account: @account, actor: nil, resource: contact,
              event_type: 'customer_contact_linked', to_value: { company_id: ids.first },
              metadata: { source: 'crm_exact_reference_backfill' })
          end
        end
      end
      report[:contacts_linked] << { contact_id: contact.id, company_id: ids.first, applied: apply }
    end
  end
end
