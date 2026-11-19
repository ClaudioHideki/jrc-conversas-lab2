require 'rails_helper'

RSpec.describe JrcContactCenter::DeferredPauseRequest do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :agent) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:manager) { JrcContactCenter::DeferredPauseManager.new(account: account, member: member) }
  let(:record) do
    version = JrcContactCenter::AgentStateSnapshot.new(account_user: member).version
    manager.request!(command_id: SecureRandom.uuid, expected_state_version: version, reason_code: 'lunch',
                     expected_request_revision: JrcContactCenter::DeferredPauseRevision.token(account: account, member: member))
  end
  let(:connection) { described_class.connection }

  before { account.enable_features!('jrc_contact_center') }

  include_context 'with a native pending voice ACW for deferred pause'

  it 'preserves request identity and private body against direct updates' do
    record
    expect do
      described_class.transaction(requires_new: true) do
        connection.execute("UPDATE jrc_contact_center_deferred_pause_requests SET reason_code='coffee' WHERE id=#{record.id}")
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /Deferred pause request is immutable/)
    expect(record.reload.reason_code).to eq('lunch')
  end

  it 'retains individual request history rather than deleting it after withdrawal' do
    manager.cancel!(record.request_id)
    expect do
      described_class.transaction(requires_new: true) { record.destroy! }
    end.to raise_error(ActiveRecord::StatementInvalid, /Deferred pause history is immutable/)
    expect(record.reload.state).to eq('cancelled')
  end

  it 'does not let terminal history become an active request again through raw SQL' do
    manager.cancel!(record.request_id)
    expect do
      described_class.transaction(requires_new: true) do
        connection.execute("UPDATE jrc_contact_center_deferred_pause_requests SET state='pending', finished_at=NULL WHERE id=#{record.id}")
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /Deferred pause request is immutable/)
    expect(record.reload.state).to eq('cancelled')
  end

  it 'requires the corresponding real native pause event before accepting an applied receipt' do
    record
    expect do
      described_class.transaction(requires_new: true) { record.update!(state: 'applied', finished_at: Time.current) }
    end.to raise_error(ActiveRecord::StatementInvalid, /Deferred pause native event required/)
    expect(record.reload.state).to eq('pending')
  end

  it 'does not allow moving an existing request into another account' do
    other = create(:account)
    record
    expect do
      described_class.transaction(requires_new: true) do
        connection.execute("UPDATE jrc_contact_center_deferred_pause_requests SET account_id=#{other.id} WHERE id=#{record.id}")
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /Deferred pause request is immutable/)
    expect(record.reload.account_id).to eq(account.id)
  end

  it 'keeps the exact structural receipt valid when the reviewed migration is reexecuted' do
    require Rails.root.join('db/migrate/20261119193000_create_contact_center_deferred_pause_requests')
    record
    expect { CreateContactCenterDeferredPauseRequests.new.up }.not_to(change(described_class, :count))
    expect(record.reload.state).to eq('pending')
  end

  it 'rejects a missing active-request uniqueness index even if columns and checks remain present' do
    require Rails.root.join('db/migrate/20261119193000_create_contact_center_deferred_pause_requests')
    record
    expect do
      described_class.transaction(requires_new: true) do
        connection.execute('DROP INDEX cc_deferred_pause_active_key')
        CreateContactCenterDeferredPauseRequests.new.up
      end
    end.to raise_error(ActiveRecord::MigrationError, /Unexpected deferred pause schema/)
    expect(record.reload.state).to eq('pending')
  end

  it 'preserves the existing account retirement block when native attendance history remains' do
    record
    id = account.id
    JrcContactCenter::Qualification.where(account: account).destroy_all
    JrcContactCenter::CallLeg.where(account: account).destroy_all
    JrcContactCenter::CallSession.where(account: account).destroy_all
    expect do
      described_class.transaction(requires_new: true) { account.destroy! }
    end.to raise_error(ActiveRecord::InvalidForeignKey, /jrc_contact_center_agent_state_events/)
    expect(described_class.where(account_id: id).pluck(:id)).to eq([record.id])
    expect(Account.exists?(id)).to be(true)
    expect(JrcContactCenter::AgentStateEvent.where(account_id: id)).to be_present
  end

  it 'permits the native account cascade for a synthetic identity with no attendance history' do
    other = create(:account)
    user = create(:user, account: other)
    membership = other.account_users.find_by!(user: user)
    row = described_class.create!(
      account: other, account_user: membership, actor_user_id: user.id, request_id: SecureRandom.uuid, state: 'pending',
      reason_code: 'lunch', reason_label: 'SYNTHETIC cascade boundary', request_digest: 'a' * 64, catalog_revision: 'b' * 64
    )
    other.destroy!
    expect(described_class.exists?(row.id)).to be(false)
    expect(Account.exists?(other.id)).to be(false)
  end
end
