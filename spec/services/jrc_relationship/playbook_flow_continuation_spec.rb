require 'rails_helper'

RSpec.describe JrcRelationship::PlaybookFlowContinuation do
  include_context 'with a published relationship Flow'

  it 'previews an input without persistence and starts the exact published run in delayed state' do
    data = review
    expect(data).to include('state' => 'preview', 'status' => 'waiting', 'reason' => nil)
    expect(JrcFlowRun.where(flow: flow)).not_to exist
    run = start_continuation
    expect(run).to have_attributes(status: 'delayed', node_id: 'node1')
  end

  it 'resumes the committed delay and consumes a real incoming contact message once' do
    run = wake_continuation(start_continuation)
    expect(run).to have_attributes(status: 'waiting', node_id: 'node2')
    message = client_reply
    JrcFlows::Runner.new(run).perform(message: message)
    expect(run.reload.status).to eq('completed')
    expect(run.variables['reply']).to eq(message.content)
    expect(flow_messages(run).map(&:content)).to eq(["Reviewed response #{message.content}"])
    expect { JrcFlows::Runner.new(run).perform(message: message) }.not_to(change { flow_messages(run).length })
  end

  it 'uses the persisted authenticated message rather than caller-edited in-memory input' do
    run = wake_continuation(start_continuation)
    message = client_reply(content: 'Persisted native contact response')
    message.content = 'Unpersisted caller content'
    JrcFlows::Runner.new(run).perform(message: message)
    expect(run.reload.status).to eq('completed')
    expect(run.variables['reply']).to eq('Persisted native contact response')
    expect(flow_messages(run).map(&:content)).to eq(['Reviewed response Persisted native contact response'])
  end

  it 'rejects an early wake and an obsolete timer without bypassing the native wake version' do
    run = start_continuation
    JrcRelationship::PlaybookFlowResumeJob.perform_now(run.id, run.wake_version)
    expect(run.reload.status).to eq('delayed')
    old_version = run.wake_version
    wake_continuation(run)
    travel_to(run.wake_at, with_usec: true) { JrcRelationship::PlaybookFlowResumeJob.perform_now(run.id, old_version) }
    expect(run.reload.status).to eq('waiting')
  end

  it 'takes the published timeout path and does not invent a client response or note' do
    run = wake_continuation(start_continuation)
    wake_continuation(run)
    expect(run.status).to eq('completed')
    expect(run.variables).not_to have_key('reply')
    expect(flow_messages(run)).to be_empty
  end

  it 'blocks a revoked original actor during a persisted delay' do
    run = start_continuation
    sd_account_user.update!(role: :agent)
    wake_continuation(run)
    expect(run.status).to eq('paused')
    expect(flow_messages(run)).to be_empty
  end

  it 'invalidates a revoked original Unit grant instead of using its old signature' do
    run = start_continuation
    sd_membership.update!(active: false)
    wake_continuation(run)
    expect(run.status).to eq('paused')
    expect(flow_messages(run)).to be_empty
  end

  context 'with a separately authorized publisher' do
    let(:publisher) { create(:user, account: sd_account, role: :administrator) }
    let(:flow) { super().tap { |record| record.update!(created_by: publisher) } }

    it 'does not substitute the still-authorized publisher for the revoked original actor' do
      run = start_continuation
      sd_account_user.update!(role: :agent)
      wake_continuation(run)
      expect(run.status).to eq('paused')
      expect(sd_account.account_users.find_by!(user: publisher)).to be_administrator
      expect(flow_messages(run)).to be_empty
    end

    it 'rechecks the publisher grant in addition to the immutable original actor' do
      run = start_continuation
      sd_account.account_users.find_by!(user: publisher).update!(role: :agent)
      wake_continuation(run)
      expect(run.status).to eq('paused')
      expect(sd_account_user.reload).to be_administrator
      expect(flow_messages(run)).to be_empty
    end
  end

  it 'blocks a changed native contact link even when the run variables claim the original contact' do
    run = wake_continuation(start_continuation)
    other = create(:contact, account: sd_account)
    conversation.contact_inbox.update!(contact: other)
    JrcFlows::Runner.new(run).perform(message: client_reply)
    expect(run.reload.status).to eq('paused')
    expect(flow_messages(run)).to be_empty
  end

  it 'rejects a foreign sender instead of using a client supplied sender name' do
    run = wake_continuation(start_continuation)
    message = client_reply(contact: create(:contact, account: sd_foreign_account))
    JrcFlows::Runner.new(run).perform(message: message)
    expect(run.reload.status).to eq('paused')
    expect(flow_messages(run)).to be_empty
  end

  it 'invalidates an expired approval at the exact server deadline' do
    run = start_continuation
    travel_to(Time.iso8601(review.fetch('approval_expires_at')), with_usec: true) do
      JrcRelationship::PlaybookFlowResumeJob.perform_now(run.id, run.wake_version)
    end
    expect(run.reload.status).to eq('paused')
    expect(flow_messages(run)).to be_empty
  end

  it 'blocks a changed Flow graph even if a direct update preserved lock_version' do
    run = start_continuation
    changed = graph.deep_dup
    changed['nodes'][3]['data']['text'] = 'Unreviewed effect'
    tamper_flow_graph(changed)
    wake_continuation(run)
    expect(run.status).to eq('paused')
    expect(flow_messages(run)).to be_empty
  end

  it 'keeps an unstamped managed origin fail closed instead of falling back to a legacy run' do
    run = start_continuation
    run.update!(settings: run.settings.except(JrcRelationship::PlaybookFlow::STAMP_KEY))
    wake_continuation(run)
    expect(run.status).to eq('paused')
    expect(flow_messages(run)).to be_empty
  end

  it 'does not use editable input variables as policy, approval or origin authority' do
    run = wake_continuation(start_continuation)
    run.update!(variables: run.variables.merge('_relationship_playbook' => { 'approved_phase' => 3, 'approval_token' => 'invented' }))
    JrcFlows::Runner.new(run).perform(message: client_reply)
    expect(run.reload.status).to eq('completed')
    expect(flow_messages(run).length).to eq(1)
  end

  it 'keeps authorization revoked despite forged approval flags in input variables' do
    run = wake_continuation(start_continuation)
    run.update!(variables: run.variables.merge('approval_required' => false, 'approved_phase' => 3))
    sd_account_user.update!(role: :agent)
    JrcFlows::Runner.new(run).perform(message: client_reply)
    expect(run.reload.status).to eq('paused')
    expect(flow_messages(run)).to be_empty
  end

  it 'requires a published execution and explicit approval before writing a run' do
    expect(start_continuation(token: nil)).to include('state' => 'blocked', 'reason' => 'explicit_flow_approval_required')
    unbound = adapter.preview(assignment: assignment, step: step, source_key: source_key)
    expect(start_continuation(origin: nil, digest: unbound.fetch('payload_digest')))
      .to include('state' => 'blocked', 'reason' => 'playbook_flow_native_origin_required')
    expect(JrcFlowRun.where(flow: flow)).not_to exist
  end

  it 'rejects a copied approval with a changed reviewed scope or signature' do
    token = review.fetch('approval_token')
    expect(start_continuation(token: "#{token}tampered")).to include('state' => 'blocked', 'reason' => 'playbook_flow_approval_invalid_or_expired')
    altered = review.fetch('payload_digest').dup
    altered[0] = altered[0] == 'a' ? 'b' : 'a'
    expect { start_continuation(digest: altered) }.to raise_error(ArgumentError, /payload changed/)
    expect(JrcFlowRun.where(flow: flow)).not_to exist
  end

  it 'projects an invalid approval as a signed native denial without rewriting the pending immutable execution' do
    token = review.fetch('approval_token')
    snapshot = execution.snapshot.deep_dup
    start_continuation(token: "#{token}tampered")
    projected = adapter.projection(execution: execution)
    expect(projected.first).to include('state' => 'blocked', 'reason' => 'playbook_flow_approval_invalid_or_expired')
    expect(projected.to_json).not_to include(token)
    expect(execution.reload.snapshot).to eq(snapshot)
    expect { start_continuation }.not_to(change { [JrcFlowRun.count, JrcCrm::AuditEvent.count] })
    expect(JrcFlowRun.where(flow: flow)).not_to exist
  end

  it 'keeps the native legacy Runner path independent of the relationship pilot' do
    run = flow.runs.create!(account: sd_account, conversation: conversation.reload, event_key: 'native-legacy-event', graph: graph,
                            settings: flow.settings.merge('_flow_version' => flow.lock_version), node_id: 'node0')
    JrcFlows::Runner.new(run).perform
    expect(run.reload.status).to eq('delayed')
    expect(run.settings).not_to have_key(JrcRelationship::PlaybookFlow::STAMP_KEY)
  end

  it 'blocks an account feature revocation while delayed' do
    run = start_continuation
    sd_account.disable_features!('jrc_relationship')
    wake_continuation(run)
    expect(run.status).to eq('paused')
    expect(flow_messages(run)).to be_empty
  end

  context 'with an explicitly pinned CRM business unit' do
    let(:business_unit) { JrcCrm::BusinessUnit.create!(account: sd_account, code: 'R2UNIT', name: 'Explicit continuation Unit') }

    before do
      assignment.update!(business_unit: business_unit)
      policy['pilot_business_unit_ids'] = [business_unit.id]
      policy['allow_unassigned_business_unit'] = false
    end

    it 'blocks an inactive unit before the delayed effect' do
      run = start_continuation
      business_unit.update!(active: false)
      wake_continuation(run)
      expect(run.status).to eq('paused')
      expect(flow_messages(run)).to be_empty
    end

    it 'blocks a changed assignment unit instead of mapping it to a similarly named unit' do
      run = start_continuation
      replacement = JrcCrm::BusinessUnit.create!(account: sd_account, code: 'R2OTHER', name: business_unit.name)
      assignment.update!(business_unit: replacement)
      wake_continuation(run)
      expect(run.status).to eq('paused')
      expect(flow_messages(run)).to be_empty
    end
  end

  context 'with a configured native step budget' do
    before { policy['max_steps'] = 3 }

    it 'honors the boundary across delay and input instead of resetting the budget on resume' do
      run = wake_continuation(start_continuation)
      expect(run.steps).to eq(3)
      JrcFlows::Runner.new(run).perform(message: client_reply)
      expect(run.reload.status).to eq('failed')
      expect(run.error).to eq('playbook_flow_execution_failed')
      expect(flow_messages(run)).to be_empty
    end
  end

  it 'rejects a cyclic graph through the real native validator before publication' do
    cyclic = graph.deep_dup
    cyclic['edges'].find { |edge| edge['source'] == 'node3' }['target'] = 'node2'
    flow.graph = cyclic
    expect(flow).not_to be_valid
    expect(flow.errors.full_messages.join).to include('ciclo')
    expect(JrcFlowRun.where(flow: flow)).not_to exist
  end

  policy_changes = { 'phase' => 2, 'pilot_company_ids' => [], 'pilot_account_user_ids' => [], 'hourly_limit' => 1 }.freeze
  %w[playbook_flow_effects_enabled phase pilot_company_ids pilot_account_user_ids hourly_limit].each do |key|
    it "revalidates #{key} after the delay was persisted" do
      run = start_continuation
      rules = configuration.rules.deep_dup
      if key == 'playbook_flow_effects_enabled'
        rules[key] = false
      else
        rules['playbook_flow_policy'][key] = policy_changes.fetch(key)
      end
      configuration.update!(rules: rules, version: configuration.version + 1)
      wake_continuation(run)
      expect(run.status).to eq('paused')
      expect(flow_messages(run)).to be_empty
    end
  end
end
