require 'rails_helper'

RSpec.describe JrcContactCenter::IvrDraft do
  let(:account) { create(:account) }
  let(:operator) { create(:user, :contact_center_eligible, account: account) }
  let(:member) { account.account_users.find_by!(user: operator) }
  let(:unit) { JrcContactCenter::Unit.create!(account: account, code: 'LOCAL', name: 'SYNTHETIC local unit', kind: 'sac') }
  let(:definition) { { 'schema_version' => 1, 'start' => 'end', 'nodes' => [{ 'id' => 'end', 'type' => 'end' }] } }
  let(:values) do
    { account: account, revision: 1, name: 'SYNTHETIC local draft', status: 'draft', definition: definition,
      actor_account_user_id: member.id, actor_user_id: operator.id, request_id: SecureRandom.uuid }
  end
  let(:draft) do
    described_class.transaction do
      row = described_class.create!(account: account, unit: unit, scope_snapshot: {})
      JrcContactCenter::IvrDraftVersion.create!(values.merge(ivr_draft: row))
      row.reload
    end
  end
  let(:version) { draft.latest_version }

  it 'preserves a native account/unit scope and computes a digest on the immutable revision' do
    expect(draft.scope_snapshot).to eq('account_id' => account.id.to_s, 'unit_id' => unit.id.to_s,
                                       'queue_id' => nil, 'issuer_company_id' => nil, 'business_unit_id' => nil)
    expect(version.reload.integrity_sha256).to match(/\A[0-9a-f]{64}\z/)
    expect(version.definition).to eq(definition)
  end

  it 'captures corporate scope at creation rather than trusting a client-supplied snapshot' do
    company = JrcCustomers::Company.create!(account: account, name: 'SYNTHETIC issuer', relationship_type: 'internal', active: true)
    business_unit = JrcCrm::BusinessUnit.create!(account: account, operating_company: company, name: 'SYNTHETIC business',
                                                 code: 'LOCAL', active: true)
    unit.update!(settings: { 'issuer_company_id' => company.id, 'business_unit_id' => business_unit.id })
    expect(draft.scope_snapshot).to include('issuer_company_id' => company.id.to_s,
                                            'business_unit_id' => business_unit.id.to_s)
    unit.update!(settings: {})
    expect(draft.reload.scope_snapshot).to include('issuer_company_id' => company.id.to_s, 'business_unit_id' => business_unit.id.to_s)
  end

  it 'supports a new revision without changing the original and rejects gaps' do
    first = version.attributes
    next_version = JrcContactCenter::IvrDraftVersion.create!(values.merge(ivr_draft: draft, revision: 2,
                                                                          name: 'SYNTHETIC revised', request_id: SecureRandom.uuid))
    expect(draft.latest_version).to eq(next_version)
    expect(version.reload.attributes).to eq(first)
    expect do
      JrcContactCenter::IvrDraftVersion.transaction(requires_new: true) do
        JrcContactCenter::IvrDraftVersion.create!(values.merge(ivr_draft: draft, revision: 4, request_id: SecureRandom.uuid))
      end
    end.to raise_error(ActiveRecord::StatementInvalid)
    expect(draft.versions.count).to eq(2)
  end

  it 'does not accept a repeated request UUID as a new operation' do
    version
    expect do
      JrcContactCenter::IvrDraftVersion.transaction(requires_new: true) do
        JrcContactCenter::IvrDraftVersion.create!(values.merge(ivr_draft: draft, revision: 2))
      end
    end.to raise_error(ActiveRecord::RecordNotUnique)
    expect(draft.versions.count).to eq(1)
  end

  it 'rejects an actor from another account without discarding the valid initial revision' do
    other = create(:user, account: create(:account))
    other_member = other.account_users.first!
    version
    expect do
      JrcContactCenter::IvrDraftVersion.transaction(requires_new: true) do
        JrcContactCenter::IvrDraftVersion.create!(values.merge(ivr_draft: draft, revision: 2, request_id: SecureRandom.uuid,
                                                               actor_account_user_id: other_member.id, actor_user_id: other.id))
      end
    end.to raise_error(ActiveRecord::StatementInvalid)
    expect(draft.versions.count).to eq(1)
  end

  it 'keeps historical actor identifiers after native account membership removal' do
    receipt = version.reload.attributes
    member.delete
    expect(version.reload.attributes).to eq(receipt)
  end

  %i[update delete].each do |operation|
    it "rejects bulk #{operation} of an existing revision in PostgreSQL" do
      version
      expect do
        described_class.transaction(requires_new: true) do
          connection = described_class.connection
          table = JrcContactCenter::IvrDraftVersion.table_name
          command = operation == :update ? "UPDATE #{table} SET name = 'not authorized'" : "DELETE FROM #{table}"
          connection.execute("#{command} WHERE id = #{connection.quote(version.id)}")
        end
      end.to raise_error(ActiveRecord::StatementInvalid)
      expect(version.reload.name).to eq(values.fetch(:name))
    end

    it "rejects bulk #{operation} of the draft identity in PostgreSQL" do
      draft
      expect do
        described_class.transaction(requires_new: true) do
          connection = described_class.connection
          table = described_class.table_name
          command = operation == :update ? "UPDATE #{table} SET scope_snapshot = '{}'::jsonb" : "DELETE FROM #{table}"
          connection.execute("#{command} WHERE id = #{connection.quote(draft.id)}")
        end
      end.to raise_error(ActiveRecord::StatementInvalid)
      expect(draft.reload.unit_id).to eq(unit.id)
    end
  end

  it 'also preserves append-only behavior at the native ActiveRecord boundary' do
    expect { version.update!(name: 'not authorized') }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { version.delete }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { draft.update!(scope_snapshot: {}) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { draft.delete }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it 'does not allow a unit with revision history to be deleted on its own' do
    draft
    expect do
      described_class.transaction(requires_new: true) do
        JrcContactCenter::Unit.where(id: unit.id).delete_all
        described_class.connection.execute('SET CONSTRAINTS cc_ivr_draft_unit_account_fk IMMEDIATE')
      end
    end.to raise_error(ActiveRecord::InvalidForeignKey)
    expect(draft.reload.unit_id).to eq(unit.id)
  end

  it 'preserves the native restriction against account deletion before its operational units' do
    version
    expect do
      described_class.transaction(requires_new: true) { account.delete }
    end.to raise_error(ActiveRecord::InvalidForeignKey)
    expect(draft.reload.unit_id).to eq(unit.id)
    expect(draft.versions.count).to eq(1)
  end

  it 'supports atomic unit-before-account retirement without orphaning immutable history' do
    version
    described_class.transaction do
      JrcContactCenter::Unit.where(id: unit.id).delete_all
      account.delete
    end
    expect(described_class.where(account_id: account.id)).to be_empty
    expect(JrcContactCenter::IvrDraftVersion.where(account_id: account.id)).to be_empty
  end

  it 'does not commit an identity without its initial revision' do
    expect do
      described_class.transaction(requires_new: true) do
        described_class.create!(account: account, unit: unit, scope_snapshot: {})
        described_class.connection.execute('SET CONSTRAINTS cc_ivr_first_version_guard IMMEDIATE')
      end
    end.to raise_error(ActiveRecord::StatementInvalid)
    expect(described_class.where(account_id: account.id)).to be_empty
  end

  it 'rejects a unit from another account at the SQL boundary' do
    other_unit = JrcContactCenter::Unit.create!(account: create(:account), code: 'FOREIGN', name: 'SYNTHETIC foreign', kind: 'sac')
    expect do
      described_class.transaction(requires_new: true) do
        described_class.create!(account: account, unit: other_unit, scope_snapshot: {})
      end
    end.to raise_error(ActiveRecord::StatementInvalid)
    expect(described_class.where(account_id: account.id)).to be_empty
  end
end
