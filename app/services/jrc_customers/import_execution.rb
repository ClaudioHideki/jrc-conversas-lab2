# One reviewed, bounded CSV is atomic. Native writers keep their permissions,
# validations, counters and audit; a repeated acknowledgement never writes twice.
class JrcCustomers::ImportExecution
  WRITE_ACTIONS = %w[create update].freeze
  NO_WRITE_ACTIONS = %w[skip reference].freeze

  def initialize(account:, actor:)
    @account = account
    @actor = actor
    @runs = JrcCustomers::ImportRuns.new(account: account, actor: actor)
    @review = JrcCustomers::ImportReview.new(account: account, actor: actor)
    @directory = JrcCustomers::ContactDirectory.new(account: account, actor: actor)
  end

  def apply!(id:, token:, confirmed:)
    raise JrcCustomers::ImportFile::InvalidFile, 'Explicit confirmation is required' unless confirmed == true

    attempt = {}
    @account.with_lock do
      run = @runs.find(id)
      run.lock!
      @review.verify!(run, token)
      run.completed? ? run : apply_reviewed!(run, attempt)
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique, ActiveRecord::InvalidForeignKey
    preserve_failure!(id, attempt)
    raise
  end

  private

  def apply_reviewed!(run, attempt)
    raise JrcCustomers::ImportFile::InvalidFile, 'Preview again before retrying this import' unless run.pending?

    attempt[:revision] = run.source_metadata.fetch('review_revision')
    attempt[:started_at] = Time.current
    plan = reviewed_plan!(run)
    apply_records!(run, plan)
    JrcCustomers::ImportAccess.new(account: @account, actor: @actor).authorize!(kind: run.source_metadata.fetch('kind'))
    finish!(run, plan, attempt.fetch(:started_at))
    run
  end

  def reviewed_plan!(run)
    lock_targets!(run)
    plan = @review.current_plan(run)
    if plan.errors.any? || plan.digest != run.source_metadata.fetch('review_digest')
      raise JrcCustomers::MergePreserver::Conflict, 'Records changed after preview; review this import again'
    end

    plan
  end

  def apply_records!(run, plan)
    companies = apply_companies!(run, plan.rows.select { |row| row.fetch(:entity) == 'company' })
    plan.rows.select { |row| row.fetch(:entity) == 'contact' }.each { |row| apply_contact!(run, row, companies) }
  end

  def lock_targets!(run)
    targets = run.source_metadata.fetch('lock_targets')
    companies = JrcCrm::CorporateCoverage.new(account: @account, user: @actor).companies(@account.master_companies)
    companies.where(id: targets.fetch('company')).order(:id).lock.load
    contacts = @directory.scope.where(id: targets.fetch('contact'))
    contacts.order(:id).lock.load
    JrcCustomers::SigningIdentity.where(account_id: @account.id, contact_id: contacts.select(:id)).order(:id).lock.load
  end

  def apply_companies!(run, rows)
    ids = {}
    rows.each do |row|
      id = company_id_for(row, ids)
      ids[row.fetch(:line)] = id
      record_result!(run, row, id)
    end
    ids
  end

  def company_id_for(row, ids)
    return ids.fetch(row.fetch(:reference_line)) if row.fetch(:action) == 'reference'
    return row.fetch(:record_id) if row.fetch(:action) == 'skip'

    company = row[:record_id] ? @account.master_companies.find(row[:record_id]) : @account.master_companies.new
    JrcCustomers::CompanyWriter.new(account: @account, actor: @actor)
                               .save!(company: company, attributes: row.fetch(:attributes), expected_revision: row[:revision]).id
  end

  def apply_contact!(run, row, companies)
    return record_result!(run, row, row.fetch(:record_id)) if row.fetch(:action) == 'skip'

    attributes = contact_attributes(row, companies)
    writer = JrcCustomers::CompanyContactWriter.new(account: @account, actor: @actor)
    confirmations = run.source_metadata.fetch('options').fetch('confirmations', {})
    contact = save_contact!(writer, row, attributes, confirmations)
    preserve_identity!(contact, row)
    record_result!(run, row, contact.id)
  end

  def contact_attributes(row, companies)
    attributes = row.fetch(:attributes).deep_dup
    attributes['company_id'] = companies.fetch(row.fetch(:company_line)) if row[:company_line]
    if row.fetch(:labels).any?
      prior = row[:record_id] ? @directory.find(row[:record_id]).label_list : []
      attributes['label_list'] = (prior + row.fetch(:labels)).uniq
    end
    attributes
  end

  def save_contact!(writer, row, attributes, confirmations)
    if row[:action] == 'create'
      return writer.create_imported!(attributes: attributes, confirm_primary_change: confirmations.fetch('primary_change', false))
    end

    writer.update!(id: row.fetch(:record_id), attributes: attributes,
                   confirm_reassignment: confirmations.fetch('reassignment', false),
                   confirm_primary_change: confirmations.fetch('primary_change', false),
                   imported: true)
  end

  def preserve_identity!(contact, row)
    value = row[:personal_identifier]
    return unless value

    current = JrcCustomers::SigningIdentity.find_by(account_id: @account.id, contact_id: contact.id)
    return if current&.personal_tax_identifier == JrcCustomers::TaxIdentifier.normalize(value)

    writer = JrcCustomers::SigningIdentityWriter.new(account: @account, actor: @actor)
    writer.save!(contact_id: contact.id, personal_tax_identifier: value, expected_revision: row.fetch(:identity_revision))
  end

  def record_result!(run, row, id)
    run.items.create!(source_provider: 'customer_master_csv', source_object_type: row.fetch(:entity), source_object_id: row.fetch(:line).to_s,
                      chatwoot_record_type: row.fetch(:entity) == 'company' ? 'Company' : 'Contact', chatwoot_record_id: id,
                      status: NO_WRITE_ACTIONS.include?(row.fetch(:action)) ? :skipped : :imported,
                      metadata: { line: row.fetch(:line), action: row.fetch(:action), fields: row.fetch(:attributes).keys.sort })
  end

  def finish!(run, plan, started_at)
    applied = plan.rows.count { |row| WRITE_ACTIONS.include?(row.fetch(:action)) }
    revision = run.source_metadata.fetch('review_revision')
    run.update!(status: :completed, started_at: started_at, completed_at: Time.current, processing_errors: nil,
                processed_records: plan.totals.fetch('total_rows'), stats: plan.totals.merge('applied_entities' => applied))
    JrcCustomers::Audit.record!(account: @account, actor: @actor, resource: run, event_type: 'customer_import_applied',
                                metadata: { sha256: run.source_metadata.fetch('sha256'), review_revision: revision,
                                            totals: run.stats })
  end

  def preserve_failure!(id, attempt)
    return if attempt.blank?

    @account.with_lock do
      run = @runs.find(id)
      run.lock!
      next unless run.pending? && run.source_metadata.fetch('review_revision') == attempt.fetch(:revision)

      run.update!(status: :failed, processed_records: 0, started_at: attempt.fetch(:started_at), completed_at: Time.current,
                  last_error_at: Time.current, processing_errors: 'Import rolled back; preview again')
      run.import_errors.create!(error_code: 'APPLY_ROLLED_BACK', message: 'No import changes were saved; review and try again',
                                details: { kind: 'failed', review_revision: attempt.fetch(:revision), started_at: run.started_at.iso8601(6),
                                           failed_at: run.completed_at.iso8601(6) })
    end
  rescue StandardError => e
    Rails.logger.warn("customer_import_failure_checkpoint_pending class=#{e.class.name}")
  end
end
