# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcContactCenter::RecordingTaskLink, :pabx do
  include_context 'with native manual recording task destination'

  let(:link) { JrcContactCenter::RecordingTaskWrite.new(account: account, member: member).call(record.id, input) }

  it 'has a real account cascade, a unique account/request key and source paging index in PostgreSQL' do
    table = described_class.table_name
    foreign = ApplicationRecord.connection.foreign_keys(table)
    expect(foreign.length).to eq(1)
    expect(foreign.first).to have_attributes(to_table: 'accounts', column: 'account_id', on_delete: :cascade)
    indexes = ApplicationRecord.connection.indexes(table)
    expect(indexes.find { |item| item.name == 'cc_recording_task_request' }).to have_attributes(unique: true)
    expect(indexes.find { |item| item.name == 'cc_recording_task_source' }.columns).to eq(%w[account_id recording_id id])
  end

  it 'has real active append and immutability triggers in the loaded schema' do
    triggers = ApplicationRecord.connection.select_values(<<~SQL)
      SELECT tgname FROM pg_trigger
      WHERE tgrelid = 'jrc_contact_center_recording_task_links'::regclass AND NOT tgisinternal AND tgenabled = 'O'
    SQL
    expect(triggers.sort).to eq(%w[cc_recording_task_append_guard cc_recording_task_immutable_guard])
  end

  it 'preserves the receipt when its native task is removed by the existing Projects lifecycle' do
    row = link
    original = row.attributes
    JrcProjects::Task.where(account: account).find(row.task_id).destroy!
    expect(row.reload.attributes).to eq(original)
    page = JrcContactCenter::RecordingTaskList.new(account: account, member: member).call(record.id)
    expect(page.fetch(:items).sole).to include(id: row.id.to_s, target: nil)
  end

  it 'refuses direct receipt deletion without changing the native Task or unrelated account data' do
    row = link
    original = row.attributes
    expect do
      ApplicationRecord.transaction(requires_new: true) { described_class.where(id: row.id).delete_all }
    end.to raise_error(ActiveRecord::StatementInvalid)
    expect(row.reload.attributes).to eq(original)
    expect(JrcProjects::Task.where(account: account).count).to eq(1)
  end

  it 'rejects forged company or business-unit scope snapshots under the actual PostgreSQL append trigger' do
    row = link
    %w[issuer_company_id business_unit_id].each do |field|
      attributes = row.attributes.except('id').merge('idempotency_key' => SecureRandom.uuid,
                                                    'scope_snapshot' => row.scope_snapshot.merge(field => '999999999'))
      expect do
        ApplicationRecord.transaction(requires_new: true) { described_class.insert_all!([attributes]) }
      end.to raise_error(ActiveRecord::StatementInvalid)
    end
    expect(described_class.where(account: account).count).to eq(1)
  end
end
