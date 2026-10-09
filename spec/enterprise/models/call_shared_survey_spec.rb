require 'rails_helper'

RSpec.describe Call do
  let(:call) { create(:call) }

  it 'evaluates successful calls once at closure and does not react to transcript updates' do
    expect { call.update!(status: 'completed') }
      .to have_enqueued_job(JrcRelationship::SurveyClosureJob).with('Call', call.id, "call:#{call.id}:#{call.provider_call_id}")
    expect { call.update!(transcript: 'Synthetic transcript') }.not_to have_enqueued_job(JrcRelationship::SurveyClosureJob)
  end

  it 'records an unsuccessful terminal call for an explicit eligibility decision without sending' do
    expect { call.update!(status: 'no_answer') }
      .to have_enqueued_job(JrcRelationship::SurveyClosureJob).with('Call', call.id, "call:#{call.id}:#{call.provider_call_id}")
    expect { call.update!(status: 'in_progress') }.not_to have_enqueued_job(JrcRelationship::SurveyClosureJob)
  end
end
