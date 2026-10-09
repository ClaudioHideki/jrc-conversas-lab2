require 'rails_helper'
require 'timeout'

RSpec.describe JrcRelationship::PlaybookFlow do
  include_context 'with a published relationship Flow'

  let(:node_definitions) { [['start', {}], ['message', { 'text' => 'Approved native customer message' }], ['end', {}]] }
  let(:run) { start_continuation }
  let(:message) { flow_messages(run).fetch(0) }

  it 'passes one authorized message through the existing native delivery boundary once' do
    expect(run.status).to eq('completed')
    attempts = []
    delivery = JrcFlows::Delivery.new(message)
    delivery.perform { attempts << message.id }
    delivery.perform { attempts << message.id }
    expect(attempts).to eq([message.id])
    expect(message.reload.content_attributes['jrc_flow_delivery']).to eq('channel_processed')
  end

  it 'blocks delivery when the original actor was revoked after message creation' do
    message
    sd_account_user.update!(role: :agent)
    attempts = []
    JrcFlows::Delivery.new(message).perform { attempts << message.id }
    expect(attempts).to be_empty
    expect(message.reload.content_attributes['jrc_flow_delivery']).to eq('cancelled')
  end

  it 'blocks a changed customer message body at the real native provider boundary' do
    message.update!(content: 'Unapproved replacement')
    attempts = []
    JrcFlows::Delivery.new(message).perform { attempts << message.id }
    expect(attempts).to be_empty
    expect(message.reload.content_attributes['jrc_flow_delivery']).to eq('cancelled')
  end

  it 'honors the account kill switch after persistence and immediately before provider I/O' do
    message
    configuration.update!(version: configuration.version + 1, rules: configuration.rules.merge('playbook_flow_effects_enabled' => false))
    attempts = []
    JrcFlows::Delivery.new(message).perform { attempts << message.id }
    expect(attempts).to be_empty
    expect(message.reload.content_attributes['jrc_flow_delivery']).to eq('cancelled')
  end

  it 'blocks altered effect records rather than trusting run variables or unsigned journal entries' do
    message
    journal = run.settings.deep_dup
    journal[JrcRelationship::PlaybookFlowContinuation::JOURNAL_KEY]['records']['node1']['message_digest'] = 'changed'
    run.update!(settings: journal)
    attempts = []
    JrcFlows::Delivery.new(message).perform { attempts << message.id }
    expect(attempts).to be_empty
    expect(message.reload.content_attributes['jrc_flow_delivery']).to eq('cancelled')
  end

  it 'stores an unknown outcome without retrying or exposing provider error/token content' do
    attempts = []
    delivery = JrcFlows::Delivery.new(message)
    token = review.fetch('approval_token')
    expect(Rails.logger).to receive(:warn).with("JRC Flows delivery=#{message.id} failed: Timeout::Error")
    delivery.perform do
      attempts << message.id
      raise Timeout::Error, "uncertain provider error #{token}"
    end
    delivery.perform { attempts << message.id }
    expect(attempts).to eq([message.id])
    expect(message.reload.content_attributes['jrc_flow_delivery']).to eq('unknown')
    expect(message.content_attributes.to_json).not_to include(token, 'uncertain provider error')
    expect { JrcRelationship::PlaybookFlowJournal.new(run.reload).verify_outcomes! }.to raise_error(ArgumentError, /outcome_unconfirmed/)
  end

  it 'keeps provider ArgumentError ambiguous after the committed dispatch claim rather than claiming a safe cancellation' do
    attempts = []
    delivery = JrcFlows::Delivery.new(message)
    delivery.perform do
      attempts << message.id
      raise ArgumentError, 'Provider failed after attempting I/O'
    end
    delivery.perform { attempts << message.id }
    expect(attempts).to eq([message.id])
    expect(message.reload.content_attributes['jrc_flow_delivery']).to eq('unknown')
  end

  it 'preserves the legacy provider error path for an unrelated native run' do
    legacy = flow.runs.create!(account: sd_account, conversation: conversation.reload, event_key: 'legacy-message-event', graph: graph,
                               settings: flow.settings.merge('_flow_version' => flow.lock_version), node_id: 'node0')
    JrcFlows::Runner.new(legacy).perform
    native_message = flow_messages(legacy).fetch(0)
    JrcFlows::Delivery.new(native_message).perform { raise ArgumentError, 'Legacy provider ambiguity' }
    expect(native_message.reload.content_attributes['jrc_flow_delivery']).to eq('unknown')
    expect(legacy.reload.status).to eq('completed')
  end

  it 'seals the native message once when the native Runner revisits the same effect node' do
    message
    run.update!(status: 'running', node_id: 'node1', finished_at: nil)
    expect { JrcFlows::Runner.new(run).perform }.not_to(change { flow_messages(run).length })
    expect(run.reload.status).to eq('completed')
  end

  it 'blocks continuation after an unknown effect outcome without generating another message' do
    message.update!(content_attributes: message.content_attributes.merge('jrc_flow_delivery' => 'unknown'))
    run.update!(status: 'running', node_id: 'node1', finished_at: nil)
    expect { JrcFlows::Runner.new(run).perform }.not_to(change { flow_messages(run).length })
    expect(run.reload.status).to eq('paused')
  end

  it 'filters direct and nested approval tokens with the real application Rails parameter configuration' do
    token = review.fetch('approval_token')
    filtered = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
                                             .filter('approval_token' => token, 'flow_approvals' => { source_key => token },
                                                     'nested' => [{ 'approval_token' => token, 'flow_approvals' => { source_key => token } }])
    expect(filtered.to_json).not_to include(token)
    expect(filtered['approval_token']).to eq('[FILTERED]')
    expect(filtered.fetch('nested').first['approval_token']).to eq('[FILTERED]')
    expect(filtered['flow_approvals']).to eq('[FILTERED]')
    expect(filtered.fetch('nested').first['flow_approvals']).to eq('[FILTERED]')
    expect(JrcRelationship::PlaybookFlowContinuation.error_message(run, StandardError.new(token))).not_to include(token)
  end

  it 'blocks expired approval immediately before provider I/O and preserves completed history visibility' do
    message
    travel_to(Time.iso8601(review.fetch('approval_expires_at')), with_usec: true) do
      attempts = []
      JrcFlows::Delivery.new(message).perform { attempts << message.id }
      expect(attempts).to be_empty
      expect(described_class.visible_run?(context: context, assignment: assignment, id: run.id)).to be(true)
    end
    expect(message.reload.content_attributes['jrc_flow_delivery']).to eq('cancelled')
  end
end
