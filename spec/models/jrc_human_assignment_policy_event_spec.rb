require 'rails_helper'

RSpec.describe JrcHumanAssignmentPolicyEvent do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:actor) { create(:user) }
  let(:event) do
    described_class.create!(account: account, inbox: inbox, user: actor,
                            previous_policy: { enabled: false }, next_policy: { enabled: true, max_open: 2 })
  end
  let(:global_event) do
    described_class.create!(account: account, user: actor,
                            previous_policy: { scope: 'GLOBAL_ACCOUNT', enabled: false, max_open: 10, inbox_ids: [] },
                            next_policy: { scope: 'GLOBAL_ACCOUNT', enabled: false, max_open: 3, inbox_ids: [] })
  end

  it 'permits an immutable account-global event without an invented inbox association' do
    expect(global_event).to be_persisted
    expect(global_event.inbox_id).to be_nil
    expect(global_event.account_id).to eq(account.id)
    expect { global_event.update!(next_policy: {}) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { global_event.delete }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  [{}, { 'scope' => 'GLOBAL' }, { 'scope' => nil }].each do |policy|
    it "rejects an inbox-less SQL insert without GLOBAL_ACCOUNT scope: #{policy.inspect}" do
      quoted_policy = described_class.connection.quote(policy.to_json)
      expect do
        described_class.transaction(requires_new: true) do
          described_class.connection.execute(<<~SQL.squish)
            INSERT INTO jrc_human_assignment_policy_events (account_id, inbox_id, previous_policy, next_policy, created_at, updated_at)
            VALUES (#{account.id}, NULL, '{}'::jsonb, #{quoted_policy}::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
          SQL
        end
      end.to raise_error(ActiveRecord::StatementInvalid, /jrc_human_policy_global_account_scope/)
    end
  end

  it 'rejects direct SQL deletion of a global event while its account still exists' do
    global_event
    expect do
      described_class.transaction(requires_new: true) { described_class.where(id: global_event.id).delete_all }
    end.to raise_error(ActiveRecord::StatementInvalid, /append-only/)
    expect(described_class.exists?(global_event.id)).to be(true)
  end

  it 'does not mistake a nil inbox for a removed parent during a nested SQL trigger' do
    global_event
    described_class.connection.execute(<<~SQL.squish)
      CREATE FUNCTION jrc_policy_test_nested_global_delete() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        DELETE FROM jrc_human_assignment_policy_events WHERE account_id = NEW.id AND inbox_id IS NULL;
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER jrc_policy_test_nested_global_delete AFTER UPDATE ON accounts
        FOR EACH ROW EXECUTE FUNCTION jrc_policy_test_nested_global_delete();
    SQL
    expect do
      described_class.transaction(requires_new: true) do
        described_class.connection.execute("UPDATE accounts SET name = 'Nested trigger probe' WHERE id = #{account.id}")
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /append-only/)
    expect(described_class.exists?(global_event.id)).to be(true)
  end

  it 'retains global account history when an unrelated inbox is removed' do
    snapshot = global_event.attributes
    event
    inbox.destroy!
    expect(described_class.exists?(event.id)).to be(false)
    expect(global_event.reload.attributes).to eq(snapshot)
  end

  it 'cascades global history only with its account while retaining another account global event' do
    retained_account = create(:account)
    retained = described_class.create!(account: retained_account, next_policy: { scope: 'GLOBAL_ACCOUNT', enabled: false })
    global_event
    account.destroy!
    expect(described_class.exists?(global_event.id)).to be(false)
    expect(described_class.exists?(retained.id)).to be(true)
  end

  it 'nullifies a removed global-event actor without changing the account-global snapshot' do
    snapshot = global_event.attributes.except('user_id')
    actor.destroy!
    expect(global_event.reload.user_id).to be_nil
    expect(global_event.attributes.except('user_id')).to eq(snapshot)
  end

  it 'allows creation but refuses model updates after persistence' do
    expect(event).to be_persisted
    expect { event.update!(next_policy: {}) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect(event.reload.next_policy).to include('enabled' => true, 'max_open' => 2)
  end

  %i[destroy! delete].each do |operation|
    it "refuses direct model #{operation} without purging history" do
      event
      expect { event.public_send(operation) }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect(described_class.exists?(event.id)).to be(true)
    end
  end

  it 'rejects bulk payload replacement at the database boundary' do
    event
    expect do
      described_class.transaction(requires_new: true) do
        described_class.connection.execute("UPDATE jrc_human_assignment_policy_events SET next_policy = '{}'::jsonb WHERE id = #{event.id}")
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /append-only/)
    expect(event.reload.next_policy).to include('enabled' => true)
  end

  it 'rejects raw SQL timestamp changes' do
    event
    expect do
      described_class.transaction(requires_new: true) do
        described_class.connection.execute(<<~SQL.squish)
          UPDATE jrc_human_assignment_policy_events
          SET created_at = created_at + interval '1 second' WHERE id = #{event.id}
        SQL
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /append-only/)
  end

  it 'rejects clearing a live actor directly rather than through its foreign key' do
    event
    expect do
      described_class.transaction(requires_new: true) do
        described_class.connection.execute("UPDATE jrc_human_assignment_policy_events SET user_id = NULL WHERE id = #{event.id}")
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /append-only/)
    expect(event.reload.user_id).to eq(actor.id)
  end

  it 'rejects bulk deletion while the account and inbox still exist' do
    event
    expect do
      described_class.transaction(requires_new: true) { described_class.where(id: event.id).delete_all }
    end.to raise_error(ActiveRecord::StatementInvalid, /append-only/)
    expect(described_class.exists?(event.id)).to be(true)
  end

  it 'guards truncation with a statement trigger verified from the catalog without executing it' do
    definition = described_class.connection.select_value(<<~SQL.squish)
      SELECT pg_get_triggerdef(oid) FROM pg_trigger
      WHERE tgrelid = 'jrc_human_assignment_policy_events'::regclass
        AND tgname = 'jrc_human_policy_immutable_truncate' AND NOT tgisinternal AND tgenabled = 'O'
    SQL
    expect(definition).to include('BEFORE TRUNCATE', 'FOR EACH STATEMENT', 'jrc_human_policy_immutable_guard')
  end

  it 'preserves the existing inbox deletion cascade without changing another inbox history' do
    retained = described_class.create!(account: account, inbox: create(:inbox, account: account), next_policy: { enabled: false })
    event
    inbox.destroy!
    expect(described_class.exists?(event.id)).to be(false)
    expect(retained.reload.next_policy).to eq('enabled' => false)
  end

  it 'preserves the existing account deletion cascade without deleting another account history' do
    foreign_account = create(:account)
    retained = described_class.create!(account: foreign_account, inbox: create(:inbox, account: foreign_account), next_policy: {})
    event
    account.destroy!
    expect(described_class.exists?(event.id)).to be(false)
    expect(described_class.exists?(retained.id)).to be(true)
  end

  it 'allows the existing user FK nullification while preserving every other event attribute' do
    snapshot = event.attributes.except('user_id')
    actor.destroy!
    expect(event.reload.user_id).to be_nil
    expect(event.attributes.except('user_id')).to eq(snapshot)
  end

  it 'allows authorized user anonymization without rewriting the event' do
    snapshot = event.attributes
    actor.skip_reconfirmation!
    actor.update!(email: "#{actor.id}@chatwoot-deleted.invalid", name: 'Anonymous')
    expect(event.reload.attributes).to eq(snapshot)
  end
end
