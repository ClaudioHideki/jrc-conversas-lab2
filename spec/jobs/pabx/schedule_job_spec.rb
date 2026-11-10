require 'rails_helper'

RSpec.describe Pabx::ScheduleJob, type: :job do
  it 'uses the native ActiveJob enqueue contract without calling a PABX provider' do
    expect(Pabx::Client).not_to receive(:new)
    expect { described_class.perform_later }.to have_enqueued_job(described_class).on_queue('scheduled_jobs')
    expect(enqueued_jobs.reverse.find { |job| job[:job] == described_class }.fetch(:args)).to eq([])
  end

  it 'accepts configured cron delivery options rather than treating the options Hash as an integration' do
    expect(Pabx::Client).not_to receive(:new)
    expect { described_class.set(queue: 'scheduled_jobs').perform_later }.to have_enqueued_job(described_class).on_queue('scheduled_jobs')
  end

  it 'preserves delayed delivery through the native ActiveJob options' do
    at = 1.minute.from_now
    expect { described_class.set(wait_until: at).perform_later }.to have_enqueued_job(described_class).on_queue('scheduled_jobs').at(at)
  end
end
