# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Service Desk history and applied SLA data', type: :model do
  include_context 'JRC Service Desk domain'
  let(:ticket) { sd_ticket }

  it 'keeps notes internal and on native Active Storage' do
    note = build(:jrc_sd_note, ticket: ticket, visibility: 'public')
    expect(note).not_to be_valid
    expect(JrcServiceDesk::TicketNote.reflect_on_attachment(:files).macro).to eq(:has_many_attached)
  end

  it 'rejects a note author from a different unit' do
    author = create(:jrc_sd_membership, unit: sd_other_unit, account_user: sd_account_user)
    expect(build(:jrc_sd_note, ticket: ticket, author_membership: author)).not_to be_valid
  end

  it 'rejects a history event whose ticket has a different scope' do
    foreign_ticket = create(:jrc_sd_ticket, unit: sd_foreign_unit)
    event = build(:jrc_sd_event, account: sd_account, unit: sd_unit, ticket: foreign_ticket, actor_membership: sd_membership)
    expect(event).not_to be_valid
  end

  { jrc_sd_event: :data, jrc_sd_note: :body, jrc_sd_snapshot: :source_version }.each do |factory, field|
    it "denies domain update/delete of persisted #{factory}" do
      record = create(factory, ticket: ticket)
      expect(record.readonly?).to be(true)
      expect { record.update_columns(field => (field == :data ? {} : 'changed')) }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect { record.delete }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect { record.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end
  end

  it 'requires an explicit valid IANA timezone' do
    snapshot = build(:jrc_sd_snapshot, ticket: ticket, timezone: 'Not/AZone')
    expect(snapshot).not_to be_valid
    expect(snapshot.errors[:timezone]).to be_present
  end

  it 'rejects nested credential fields in conditions' do
    snapshot = build(:jrc_sd_snapshot, ticket: ticket, contract_conditions: { nested: { api_key: 'fixture-not-a-real-key' } })
    expect(snapshot).not_to be_valid
  end

  it 'rejects a payload digest that does not match the conditions' do
    snapshot = build(:jrc_sd_snapshot, ticket: ticket)
    snapshot.payload_digest = 'b' * 64
    expect(snapshot).not_to be_valid
  end

  it 'does not report an uncalculated milestone as SLA met' do
    milestone = create(:jrc_sd_milestone, sla_snapshot: create(:jrc_sd_snapshot, ticket: ticket))
    expect(milestone.due_at).to be_nil
    expect(milestone.calculation_pending?).to be(true)
    expect(milestone.met?).to be_nil
  end

  it 'requires calculation provenance when a deadline is present' do
    milestone = build(:jrc_sd_milestone, sla_snapshot: create(:jrc_sd_snapshot, ticket: ticket), due_at: 1.hour.from_now)
    expect(milestone).not_to be_valid
  end

  it 'rejects a snapshot from another ticket even in the same unit' do
    another = sd_ticket
    snapshot = create(:jrc_sd_snapshot, ticket: another)
    milestone = build(:jrc_sd_milestone, sla_snapshot: snapshot, ticket: ticket)
    expect(milestone).not_to be_valid
  end

  it 'does not permit linking a conversation from another Account' do
    link = build(:jrc_sd_conversation_link, ticket: ticket, conversation: create(:conversation, account: sd_foreign_account))
    expect(link).not_to be_valid
  end
end
