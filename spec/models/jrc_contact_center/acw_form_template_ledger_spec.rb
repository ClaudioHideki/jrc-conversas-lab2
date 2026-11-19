require 'rails_helper'

RSpec.describe JrcContactCenter::AcwFormTemplate do
  let(:account) { create(:account) }
  let(:operator) { create(:user, :contact_center_eligible, account: account) }
  let(:member) { account.account_users.find_by!(user: operator) }
  let(:definition) { { 'fields' => [{ 'key' => 'detail', 'label' => 'SYNTHETIC field', 'type' => 'text', 'required' => true }] } }
  let(:values) do
    { account: account, revision: 1, name: 'SYNTHETIC local form', description: 'SYNTHETIC local description', status: 'active',
      definition: definition, actor_account_user_id: member.id, actor_user_id: operator.id, request_id: SecureRandom.uuid }
  end
  let(:form) do
    described_class.transaction do
      row = described_class.create!(account: account, scope_snapshot: { 'account_id' => 'not-authorized', 'unit_id' => 'not-authorized' })
      JrcContactCenter::AcwFormVersion.create!(values.merge(acw_form_template: row))
      row.reload
    end
  end
  let(:version) { form.latest_version }
  let(:bulk_values) do
    values.except(:account).merge(account_id: account.id, acw_form_template_id: form.id, revision: 2,
                                  request_id: SecureRandom.uuid, created_at: Time.current, integrity_sha256: '')
  end

  # Bypass ActiveRecord callbacks explicitly to prove the SQL constraints themselves.
  def insert_raw_version(values)
    connection = described_class.connection
    table = JrcContactCenter::AcwFormVersion
    columns = values.keys.map { |key| connection.quote_column_name(key) }.join(', ')
    serialized = values.map { |key, value| connection.quote(table.type_for_attribute(key.to_s).serialize(value)) }.join(', ')
    connection.execute("INSERT INTO #{connection.quote_table_name(table.table_name)} (#{columns}) VALUES (#{serialized})")
  end

  it 'computes the account scope and immutable definition digest without trusting a submitted scope' do
    expect(form.scope_snapshot).to eq('account_id' => account.id.to_s)
    expect(version.integrity_sha256).to match(/\A[0-9a-f]{64}\z/)
    expect(version.definition).to eq(definition)
  end

  it 'appends a contiguous new version without rewriting the original definition' do
    original = version.attributes
    changed = JrcContactCenter::AcwFormVersion.create!(values.merge(acw_form_template: form, revision: 2,
                                                                    name: 'SYNTHETIC next', request_id: SecureRandom.uuid))
    expect(form.latest_version).to eq(changed)
    expect(version.reload.attributes).to eq(original)
    expect(form.versions.count).to eq(2)
  end

  it 'persists a large valid compact schema even when PostgreSQL adds JSONB separator spaces' do
    values[:definition] = {
      'fields' => Array.new(50) do |i|
        { 'key' => "field-#{i}", 'label' => 'SYNTHETIC choice', 'type' => 'select', 'required' => false,
          'options' => Array.new(100) { |j| "#{j}-#{'x' * 45}" } }
      end
    }
    expect(values[:definition].to_json.bytesize).to be <= JrcContactCenter::AcwFormDefinition::MAX_BYTES
    expect(version.reload.definition).to eq(values[:definition])
    sql = "SELECT octet_length(definition::text) FROM jrc_contact_center_acw_form_versions WHERE id = #{version.id}"
    bytes = described_class.connection.select_value(sql)
    expect(bytes).to be > JrcContactCenter::AcwFormDefinition::MAX_BYTES
    expect(bytes).to be <= JrcContactCenter::AcwFormDefinition::MAX_BYTES + 8192
  end

  it 'retains a hard SQL representation-size bound when a bulk insert bypasses native model validation' do
    version
    payload = { 'fields' => Array.new(50) { |i| { 'key' => "field-#{i}", 'label' => 'x' * 6000 } } }
    row = bulk_values.merge(definition: payload)
    expect do
      described_class.transaction(requires_new: true) { insert_raw_version(row) }
    end.to raise_error(ActiveRecord::StatementInvalid) { |error| expect(error.message).to include('cc_acw_form_definition_object') }
    expect(form.versions.count).to eq(1)
  end

  [{}, { 'fields' => nil }, { 'fields' => {} }, { 'fields' => [] }, { 'fields' => [], 'unit_id' => 1 }].each do |definition|
    it "rejects an incomplete definition envelope #{definition.inspect} at the SQL boundary" do
      version
      expect do
        described_class.transaction(requires_new: true) do
          insert_raw_version(bulk_values.merge(definition: definition))
        end
      end.to raise_error(ActiveRecord::StatementInvalid)
      expect(form.versions.count).to eq(1)
    end
  end

  it 'rejects a revision gap at the database boundary even when the model validates the integer' do
    version
    expect do
      described_class.transaction(requires_new: true) do
        JrcContactCenter::AcwFormVersion.create!(values.merge(acw_form_template: form, revision: 3, request_id: SecureRandom.uuid))
      end
    end.to raise_error(ActiveRecord::StatementInvalid)
    expect(form.versions.count).to eq(1)
  end

  it 'rejects reuse of the account request identity instead of appending a second event' do
    version
    expect do
      described_class.transaction(requires_new: true) do
        JrcContactCenter::AcwFormVersion.create!(values.merge(acw_form_template: form, revision: 2))
      end
    end.to raise_error(ActiveRecord::RecordNotUnique)
    expect(form.versions.count).to eq(1)
  end

  it 'rejects an actor from another account while preserving the first revision' do
    other = create(:user, account: create(:account))
    other_member = other.account_users.first!
    version
    expect do
      described_class.transaction(requires_new: true) do
        JrcContactCenter::AcwFormVersion.create!(values.merge(acw_form_template: form, revision: 2, request_id: SecureRandom.uuid,
                                                              actor_account_user_id: other_member.id, actor_user_id: other.id))
      end
    end.to raise_error(ActiveRecord::StatementInvalid)
    expect(form.versions.count).to eq(1)
  end

  it 'does not attach a version in a different account to an existing form' do
    other = create(:user, account: create(:account))
    other_member = other.account_users.first!
    version
    expect do
      described_class.transaction(requires_new: true) do
        JrcContactCenter::AcwFormVersion.create!(values.merge(account_id: other_member.account_id, acw_form_template: form,
                                                              actor_account_user_id: other_member.id, actor_user_id: other.id,
                                                              revision: 2, request_id: SecureRandom.uuid))
      end
    end.to raise_error(ActiveRecord::StatementInvalid)
    expect(form.versions.count).to eq(1)
  end

  it 'retains historical actor IDs after the corresponding native membership is removed' do
    original = version.reload.attributes
    member.delete
    expect(version.reload.attributes).to eq(original)
  end

  %i[update delete].each do |operation|
    it "rejects raw SQL #{operation} of a version even when ActiveRecord is bypassed" do
      version
      expect do
        described_class.transaction(requires_new: true) do
          table = JrcContactCenter::AcwFormVersion.table_name
          sql = operation == :update ? "UPDATE #{table} SET name = 'not authorized'" : "DELETE FROM #{table}"
          described_class.connection.execute("#{sql} WHERE id = #{version.id}")
        end
      end.to raise_error(ActiveRecord::StatementInvalid)
      expect(version.reload.name).to eq(values.fetch(:name))
    end

    it "rejects raw SQL #{operation} of the immutable form identity" do
      form
      expect do
        described_class.transaction(requires_new: true) do
          table = described_class.table_name
          sql = operation == :update ? "UPDATE #{table} SET scope_snapshot = '{}'::jsonb" : "DELETE FROM #{table}"
          described_class.connection.execute("#{sql} WHERE id = #{form.id}")
        end
      end.to raise_error(ActiveRecord::StatementInvalid)
      expect(form.reload.scope_snapshot).to eq('account_id' => account.id.to_s)
    end
  end

  it 'also preserves append-only behavior at the native model boundary' do
    expect { version.update!(name: 'not authorized') }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { version.delete }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { form.update!(scope_snapshot: {}) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { form.delete }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it 'does not commit an identity without its initial version' do
    expect do
      described_class.transaction(requires_new: true) do
        described_class.create!(account: account, scope_snapshot: {})
        described_class.connection.execute('SET CONSTRAINTS cc_acw_form_first_version_guard IMMEDIATE')
      end
    end.to raise_error(ActiveRecord::StatementInvalid)
    expect(described_class.where(account_id: account.id)).to be_empty
  end

  it 'follows account retirement without leaving immutable roots or versions orphaned' do
    version
    account.delete
    expect(described_class.where(account_id: account.id)).to be_empty
    expect(JrcContactCenter::AcwFormVersion.where(account_id: account.id)).to be_empty
  end

  it 'accepts exact native migration reexecution without changing the version history' do
    require Rails.root.join('db/migrate/20261119190000_create_contact_center_acw_forms')
    version
    require Rails.root.join('script/jrc_call_center_acw_form_schema_probe')
    JrcContactCenter::SyntheticAcwFormSchemaProbe.record('rspec')
    expect { CreateContactCenterAcwForms.new.up }.not_to(change { form.versions.count })
  end

  it 'rejects an existing ledger whose required unique index was removed' do
    require Rails.root.join('db/migrate/20261119190000_create_contact_center_acw_forms')
    version
    expect do
      described_class.transaction(requires_new: true) do
        described_class.connection.execute('DROP INDEX cc_acw_form_request_key')
        CreateContactCenterAcwForms.new.up
      end
    end.to raise_error(ActiveRecord::MigrationError, /Unexpected ACW form ledger schema/)
    expect(form.versions.count).to eq(1)
  end

  it 'still rejects a changed status constraint even when its name and table columns were preserved' do
    require Rails.root.join('db/migrate/20261119190000_create_contact_center_acw_forms')
    version
    expect do
      described_class.transaction(requires_new: true) do
        connection = described_class.connection
        connection.execute('ALTER TABLE jrc_contact_center_acw_form_versions DROP CONSTRAINT cc_acw_form_version_state')
        connection.execute("ALTER TABLE jrc_contact_center_acw_form_versions ADD CONSTRAINT cc_acw_form_version_state " \
                           "CHECK (revision > 0 AND btrim(name) <> '' AND status::text IN ('active'::text, 'archived'::text, 'published'::text))")
        CreateContactCenterAcwForms.new.up
      end
    end.to raise_error(ActiveRecord::MigrationError, /Unexpected ACW form ledger schema/)
    expect(form.versions.count).to eq(1)
  end

end
