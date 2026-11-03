# Persists the reviewed configuration and counts, never raw CSV row values.
class JrcCustomers::ImportReview
  def initialize(account:, actor:)
    @account = account
    @actor = actor
    @runs = JrcCustomers::ImportRuns.new(account: account, actor: actor)
  end

  def preview!(id:, mapping:, options:)
    @account.with_lock do
      run = @runs.find(id)
      run.lock!
      raise JrcCustomers::ImportFile::InvalidFile, 'This import is already completed' unless run.pending? || run.failed?

      file = @runs.file(run)
      plan = JrcCustomers::ImportPlan.new(account: @account, actor: @actor, file: file, mapping: mapping, options: options).call
      preserve_review!(run, file, plan)
      { run: run, plan: plan, token: plan.errors.empty? ? verifier.generate(envelope(run), expires_in: 15.minutes) : nil }
    end
  end

  def current_plan(run)
    run = @runs.find(run.id)
    file = @runs.file(run)
    destinations = run.source_metadata.fetch('column_mapping')
    unless destinations.is_a?(Array) && destinations.size == file.headers.size
      raise JrcCustomers::ImportFile::InvalidFile, 'Review the column mapping again'
    end

    mapping = file.headers.zip(destinations).to_h
    JrcCustomers::ImportPlan.new(account: @account, actor: @actor, file: file, mapping: mapping,
                                 options: run.source_metadata.fetch('options')).call
  end

  def verify!(run, token)
    run = @runs.find(run.id)
    raise JrcCustomers::ImportFile::InvalidFile, 'Review token is required' unless token.is_a?(String) && token.bytesize <= 4096

    received = verifier.verified(token)
    return true if received == envelope(run)

    raise JrcCustomers::ImportFile::InvalidFile, 'Review expired or changed; preview again'
  end

  private

  def verifier
    Rails.application.message_verifier('jrc_customer_master_reviewed_run_v1')
  end

  def envelope(run)
    metadata = run.source_metadata
    { 'account_id' => @account.id, 'actor_id' => @actor.id, 'run_id' => run.id, 'sha256' => metadata.fetch('sha256'),
      'kind' => metadata.fetch('kind'), 'review_revision' => metadata['review_revision'], 'review_digest' => metadata['review_digest'] }
  end

  def preserve_review!(run, file, plan)
    revision = run.source_metadata.fetch('review_revision', 0) + 1
    metadata = run.source_metadata.merge('column_mapping' => file.headers.map { |header| plan.mapping.fetch(header) },
                                         'options' => plan.options.as_json, 'review_digest' => plan.digest,
                                         'lock_targets' => plan.lock_targets, 'review_revision' => revision,
                                         'reviewed_at' => Time.current.iso8601(6))
    run.update!(source_metadata: metadata, stats: plan.totals, status: :pending, processing_errors: nil, started_at: nil, completed_at: nil)
    preserve_errors!(run, plan)
    JrcCustomers::Audit.record!(account: @account, actor: @actor, resource: run, event_type: 'customer_import_previewed',
                                metadata: { review_revision: revision, sha256: metadata.fetch('sha256'), totals: plan.totals })
  end

  def preserve_errors!(run, plan)
    plan.errors.each do |error|
      run.import_errors.create!(source_object_type: 'csv_row', source_object_id: error.fetch(:line).to_s,
                                error_code: error.fetch(:code), message: error.fetch(:message),
                                details: { kind: 'preview', review_revision: run.source_metadata.fetch('review_revision'),
                                           entity: error.fetch(:entity), field: error.fetch(:field) })
    end
  end
end
