# frozen_string_literal: true
require 'rails_helper'

RSpec.describe 'Lifecycle model and database boundary constraints', type: :model do
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures

  it 'refuses changing immutable ticket service or replacing a historical version' do
    policy = lc_publish
    row = sd_ticket
    lc_execute(row, 'pause', reason_code: 'customer')
    service = JrcServiceDesk::Service.create!(account: sd_account, unit: sd_unit, name: 'Fixture', code: 'fixed', active: true)
    expect { row.reload.update!(service: service) }.to raise_error(ActiveRecord::RecordInvalid)
    expect { policy.current_version.delete }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it 'rejects direct-SQL cross-unit ticket/policy and foreign service references using database FKs' do
    lc_publish
    row = sd_ticket
    other_service = JrcServiceDesk::Service.create!(account: sd_foreign_account, unit: sd_foreign_unit, name: 'Other', code: 'other', active: true)
    expect do
      JrcServiceDesk::Base.transaction(requires_new: true) do
        JrcServiceDesk::Ticket.where(id: row.id).update_all(service_id: other_service.id)
      end
    end.to raise_error(ActiveRecord::InvalidForeignKey)
    expect(row.reload.service_id).to be_nil
  end

  it 'makes SQL reject an end author without an end timestamp rather than letting NULL pass the CHECK' do
    lc_publish; row = sd_ticket
    lc_execute(row, 'pause', reason_code: 'customer')
    pause = row.lifecycle_pauses.last
    expect do
      JrcServiceDesk::Base.transaction(requires_new: true) do
        JrcServiceDesk::LifecyclePause.where(id: pause.id).update_all(ended_by_membership_id: sd_membership.id)
      end
    end.to raise_error(ActiveRecord::StatementInvalid)
    expect(pause.reload.ended_at).to be_nil
  end

  it 'records closure once and blocks ordinary model mutation of transition payload' do
    lc_publish; row = sd_ticket
    transition = lc_execute(row, 'pause', reason_code: 'customer')
    lc_execute(row, 'resume')
    pause = row.lifecycle_pauses.last
    expect { pause.update!(ended_at: pause.ended_at + 1.second) }.to raise_error(ActiveRecord::RecordInvalid)
    expect { transition.update!(payload: {}) }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end
end
