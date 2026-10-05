require 'rails_helper'
require 'sidekiq/cron/job'

RSpec.describe 'Operations SLA schedule' do
  it 'loads a valid five-minute scheduled job without duplicate YAML keys' do
    text = Rails.root.join('config/schedule.yml').read
    keys = Psych.parse(text).root.children.each_slice(2).map { |key, _| key.value }
    expect(keys.uniq).to eq(keys)
    schedule = YAML.safe_load(text, aliases: true).fetch('jrc_operations_sla_monitor_job')
    expect(schedule).to include('cron' => '*/5 * * * *', 'class' => 'JrcOperations::SlaMonitorJob', 'queue' => 'scheduled_jobs')
    expect(Sidekiq::Cron::Job.new(schedule.merge('name' => 'jrc_operations_sla_monitor_job'))).to be_valid
    expect(JrcOperations::SlaMonitorJob.queue_name).to eq('scheduled_jobs')
  end
end
