require 'rails_helper'

RSpec.describe CsatSurveyService, :sd_concurrency do
  self.use_transactional_tests = false
  include JrcServiceDeskConcurrency

  it 'creates one survey when two resolution workers pass the initial eligibility check together' do
    account = create(:account)
    inbox = create(:channel_api, account: account).inbox
    inbox.update!(csat_survey_enabled: true)
    conversation = create(:conversation, account: account, inbox: inbox, status: :resolved)
    ready = Queue.new
    proceed = Queue.new
    records = Array.new(2) { Conversation.find(conversation.id) }
    records.each do |record|
      arrived = false
      allow(record).to receive(:can_reply?) do
        unless arrived
          arrived = true
          ready << true
          Timeout.timeout(10) { proceed.pop }
        end
        true
      end
    end
    coordinator = Thread.new do
      Timeout.timeout(10) { 2.times { ready.pop } }
      2.times { proceed << true }
    end

    operations = records.map do |record|
      lambda do
        described_class.new(conversation: record).perform
        :completed
      end
    end
    outcomes = concurrently(operations)
    coordinator.join

    expect(outcomes).to eq(%i[completed completed])
    expect(conversation.messages.where(content_type: :input_csat).count).to eq(1)
  ensure
    coordinator&.kill if coordinator&.alive?
    coordinator&.join
  end
end
