class JrcCustomers::ImportPresenter
  STAT_KEYS = %w[total_rows valid_rows invalid_rows ignored_rows error_count company_create company_update company_skip company_reference
                 contact_create contact_update contact_skip applied_entities].freeze

  def initialize(account:, actor:)
    @account = account
    @actor = actor
    @runs = JrcCustomers::ImportRuns.new(account: account, actor: actor)
  end

  def summary(run)
    { id: run.id, filename: run.name, kind: run.source_metadata.fetch('kind'), status: run.status,
      initiated_by: { id: run.initiated_by_id, name: @actor.name }, total_records: run.total_records, processed_records: run.processed_records,
      stats: run.stats.slice(*STAT_KEYS), created_at: run.created_at, started_at: run.started_at, completed_at: run.completed_at,
      reviewed_at: run.source_metadata['reviewed_at'], review_revision: run.source_metadata['review_revision'],
      can_review: run.pending? || run.failed? }
  end

  def detail(run)
    result = { payload: summary(run) }
    return result if run.completed?

    file = @runs.file(run)
    destinations = run.source_metadata['column_mapping']
    mapping = destinations ? file.headers.zip(destinations).to_h : file.metadata.fetch(:suggested_mapping)
    result.merge(file: file.metadata, column_mapping: mapping,
                 import_options: run.source_metadata.fetch('options', { 'existing' => 'skip', 'confirmations' => {} }))
  end
end
