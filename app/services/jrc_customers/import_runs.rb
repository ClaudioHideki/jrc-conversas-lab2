class JrcCustomers::ImportRuns
  def initialize(account:, actor:)
    @account = account
    @actor = actor
    @access = JrcCustomers::ImportAccess.new(account: account, actor: actor)
  end

  def scope
    kinds = @access.available_kinds
    DataImport.where(account_id: @account.id, initiated_by_id: @actor.id, data_type: 'customer_master', source_provider: 'customer_master_csv')
              .where("source_metadata ->> 'kind' IN (?)", kinds)
  end

  def find(id)
    run = scope.find(id)
    @access.authorize!(kind: run.source_metadata.fetch('kind'))
    run
  end

  def create!(content:, kind:, filename:, delimiter: nil)
    @access.authorize!(kind: kind)
    parsed = JrcCustomers::ImportFile.new(content: content, kind: kind, delimiter: delimiter)
    blob = nil
    @account.with_lock do
      @access.authorize!(kind: kind)
      run = create_record!(parsed, kind, filename)
      blob = JrcCustomers::ImportBlob.upload!(run: run, content: content)
      JrcCustomers::Audit.record!(account: @account, actor: @actor, resource: run, event_type: 'customer_import_uploaded',
                                  metadata: { sha256: parsed.sha256, kind: kind, total_records: run.total_records })
      run
    end
  rescue StandardError
    JrcCustomers::ImportBlob.clean_uncommitted(blob)
    raise
  end

  def file(run)
    run = find(run.id)
    JrcCustomers::ImportFile.new(content: JrcCustomers::ImportBlob.read!(run: run), kind: run.source_metadata.fetch('kind'),
                                 delimiter: run.source_metadata.fetch('delimiter'))
  end

  private

  def create_record!(parsed, kind, filename)
    DataImport.create!(account: @account, initiated_by: @actor, data_type: 'customer_master', source_provider: 'customer_master_csv',
                       source_type: 'csv', name: File.basename(filename.to_s.tr('\\', '/')).truncate(180),
                       import_types: kind == 'both' ? %w[companies contacts] : [kind], total_records: parsed.metadata.fetch(:row_count),
                       processed_records: 0, source_metadata: { kind: kind, sha256: parsed.sha256, delimiter: parsed.delimiter })
  end
end
