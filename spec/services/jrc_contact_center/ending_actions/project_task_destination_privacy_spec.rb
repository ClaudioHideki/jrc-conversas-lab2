require 'rails_helper'
require 'stringio'

RSpec.describe JrcContactCenter::EndingActions::ProjectTaskDestination, 'private native destination binds' do
  include_context 'with native ending execution original evidence'

  let(:marker) { 'SYNTHETIC_PRIVATE_NATIVE_TASK_23b8' }
  let(:parameters) do
    version = JrcContactCenter::EndingActionVersion.where(account: account).order(revision: :desc).first!
    values = version.definition.fetch('entries').first.fetch('actions').first.fetch('parameters').deep_dup
    values.fetch('attributes').merge!('title' => marker, 'description' => marker, 'labels' => [marker])
    values
  end

  def capture_native_task_sql
    previous = ActiveRecord::Base.logger
    output = StringIO.new
    ActiveRecord::Base.logger = ActiveSupport::Logger.new(output)
    yield
    output.string
  ensure
    ActiveRecord::Base.logger = previous
  end

  def create_private_destination
    described_class.new(account: account, member: member).call(
      parameters: parameters, trigger_at: Time.current, timezone: 'America/Sao_Paulo', correlation_id: SecureRandom.uuid
    )
  end

  it 'redacts the actual task and native audit SQL binds while preserving useful account diagnostics' do
    parameters
    task = nil
    log = capture_native_task_sql { task = create_private_destination }
    expect(log).to include('jrc_projects_tasks', 'jrc_projects_audit_events', '[FILTERED]', "[\"account_id\", #{account.id}]")
    expect(log).not_to include(marker)
    expect(task.reload).to have_attributes(title: marker, description: marker, labels: [marker])
    audit = JrcProjects::AuditEvent.find_by!(account: account, auditable_type: task.class.name, auditable_id: task.id)
    expect(audit.after_data.fetch('title')).to eq(marker)
  end

  it 'keeps destination content out of inspection without changing the persisted native task or audit' do
    task = create_private_destination
    audit = JrcProjects::AuditEvent.find_by!(account: account, auditable_type: task.class.name, auditable_id: task.id)
    expect(task.inspect).to include('title: [FILTERED]', 'description: [FILTERED]', 'custom_fields: [FILTERED]')
    expect(audit.inspect).to include('after_data: [FILTERED]')
    expect(task.inspect + audit.inspect).not_to include(marker)
    expect(task.reload.title).to eq(marker)
    expect(audit.reload.after_data.fetch('title')).to eq(marker)
  end

  it 'redacts configured native task fields from request logging without hiding authority identifiers' do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    values = filter.filter('title' => marker, 'description' => marker, 'custom_fields' => { 'labels' => [marker] },
                           'after_data' => { 'title' => marker }, 'account_id' => account.id)
    expect(values.values_at('title', 'description', 'custom_fields', 'after_data')).to eq(Array.new(4, '[FILTERED]'))
    expect(values.fetch('account_id')).to eq(account.id)
    expect(values.to_json).not_to include(marker)
  end
end
