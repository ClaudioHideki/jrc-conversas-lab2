require 'csv'

class JrcCustomers::ImportResults
  ERROR_COLUMNS = %i[line entity field code message].freeze

  def initialize(account:, actor:)
    @account = account
    @actor = actor
    @runs = JrcCustomers::ImportRuns.new(account: account, actor: actor)
  end

  def rows(run)
    @runs.find(run.id).items.where(source_object_type: %w[company contact]).order(:id)
  end

  def errors(run)
    record = @runs.find(run.id)
    record.import_errors.where("details ->> 'review_revision' = ?", record.source_metadata.fetch('review_revision', 0).to_s).order(:id)
  end

  def serialize_rows(items)
    visible = visible_records(items)
    items.map do |item|
      record = visible.fetch(item.source_object_type)[item.chatwoot_record_id]
      { id: item.id, line: item.metadata.fetch('line'), entity: item.source_object_type, action: item.metadata.fetch('action'),
        status: item.status, record_id: record&.id, name: record&.name, unavailable: record.nil? }
    end
  end

  def serialize_errors(items)
    items.map do |item|
      { id: item.id, line: item.source_object_id&.to_i, entity: item.details['entity'], field: item.details['field'],
        code: item.error_code, message: item.message, kind: item.details['kind'], created_at: item.created_at }
    end
  end

  def error_csv(run)
    data = serialize_errors(errors(run).to_a)
    csv_text = CSV.generate(col_sep: ';') do |csv|
      csv << %w[registro entidade campo codigo erro]
      data.each { |row| csv << ERROR_COLUMNS.map { |key| safe_cell(row[key]) } }
    end
    "\uFEFF#{csv_text}"
  end

  private

  def visible_records(items)
    companies = JrcCrm::CorporateCoverage.new(account: @account, user: @actor).companies(@account.master_companies)
    contacts = JrcCustomers::ContactDirectory.new(account: @account, actor: @actor).scope
    { 'company' => companies.where(id: items.select { |item| item.source_object_type == 'company' }.map(&:chatwoot_record_id)).index_by(&:id),
      'contact' => contacts.where(id: items.select { |item| item.source_object_type == 'contact' }.map(&:chatwoot_record_id)).index_by(&:id) }
  end

  def safe_cell(value)
    text = value.to_s
    text.match?(/\A[=+\-@\t\r]/) ? "'#{text}" : text
  end
end
