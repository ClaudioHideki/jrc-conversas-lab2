# frozen_string_literal: true

require 'rails_helper'
require 'timeout'

RSpec.describe 'Contact Center qualification concurrent retries', type: :service do
  self.use_transactional_tests = false

  it 'serializes two real connections into one pending record and one immutable completion' do
    stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook').to_return(status: 200, body: '{}')
    stub_request(:get, 'https://waba.360dialog.io/v1/configs/templates').to_return(status: 200, body: '{"waba_templates":[]}', headers: { 'Content-Type' => 'application/json' })
    account = create(:account)
    account.enable_features!('jrc_contact_center')
    agent = create(:user, account: account, role: :agent)
    member = account.account_users.find_by!(user: agent)
    inbox = create(:inbox, account: account, channel: create(:channel_whatsapp, account: account,
                                                         phone_number: "+5599#{SecureRandom.random_number(10**9).to_s.rjust(9, '0')}"))
    conversation = create(:conversation, account: account, inbox: inbox, assignee: agent)
    gate = Queue.new
    results = Queue.new
    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          gate.pop
          manager = JrcContactCenter::QualificationManager.new(account: Account.find(account.id), member: AccountUser.find(member.id))
          record = manager.start!(conversation: Conversation.find(conversation.id))
          manager.complete!(record, { reason_code: 'order', outcome_code: 'completed', notes: 'Concurrent completion' })
          results << record.id
        rescue StandardError => error
          results << error
        end
      end
    end
    2.times { gate << true }
    Timeout.timeout(30) { threads.each(&:join) }
    values = 2.times.map { results.pop }
    expect(values).to all(be_a(Integer))
    expect(values.uniq.size).to eq(1)
    expect(JrcContactCenter::Qualification.where(conversation: conversation).count).to eq(1)
    expect(JrcContactCenter::Qualification.find(values.first)).to have_attributes(notes: 'Concurrent completion', outcome_code: 'completed')
    expect(JrcContactCenter::AgentStateEvent.where(account: account, external_event_id: "qualification:#{values.first}:completed").count).to eq(1)
  ensure
    threads&.each { |thread| thread.kill if thread.alive? }
  end
end
