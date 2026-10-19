require 'rails_helper'

RSpec.describe 'NICO bounded workflows and approved company knowledge' do
  let(:account) { create(:account, custom_attributes: { 'nico_enabled' => true }) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:operator) { JrcNico::OperatorSession.new(account: account, user: user) }

  def command(workflow, state)
    operator.session.commands.create!(request_id: SecureRandom.uuid, message: 'Synthetic bounded workflow', status: state,
                                       execution_context: { 'workflow_id' => workflow })
  end

  it 'stops at twelve persisted steps before another provider plan or tool execution' do
    workflow = SecureRandom.uuid
    operator.session.update!(context: operator.session.context.merge('active_workflow_id' => workflow))
    previous = Array.new(12) { command(workflow, 'succeeded') }.last
    expect(JrcNico::OperationalInference).not_to receive(:call)
    expect { operator.continue_workflow(previous) }.not_to change(JrcNico::Command, :count)
    expect(operator.session.reload.messages.last.fetch('content')).to include('doze etapas')
  end

  it 'does not continue across an uncertain native action' do
    workflow = SecureRandom.uuid
    operator.session.update!(context: operator.session.context.merge('active_workflow_id' => workflow))
    command(workflow, 'unknown')
    previous = command(workflow, 'succeeded')
    expect(JrcNico::OperationalInference).not_to receive(:call)
    expect { operator.continue_workflow(previous) }.not_to change(JrcNico::Command, :count)
  end

  it 'retrieves only approved knowledge from the current company and removes it after an edit revokes approval' do
    document = JrcNico::KnowledgeDocument.create!(account: account, author: user, approved_by: user, approved_at: Time.current,
                                                  title: 'Synthetic telescope', body: 'Synthetic telescope procedure')
    JrcNico::KnowledgeDocument.create!(account: account, author: user, title: 'Synthetic telescope draft', body: 'Unapproved telescope')
    other = create(:account)
    owner = create(:user, account: other, role: :administrator)
    JrcNico::KnowledgeDocument.create!(account: other, author: owner, approved_by: owner, approved_at: Time.current,
                                      title: 'Synthetic telescope foreign', body: 'Foreign telescope')
    executor = JrcNico::ToolExecutor.new(operator.access)
    expect(executor.call('search_knowledge', { 'query' => 'telescope' }).pluck(:id)).to eq([document.id])
    document.update!(body: 'Revised telescope procedure')
    expect(document.reload.approved_at).to be_nil
    expect(executor.call('search_knowledge', { 'query' => 'telescope' })).to eq([])
  end
end
