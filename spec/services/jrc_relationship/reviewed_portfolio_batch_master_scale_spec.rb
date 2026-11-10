require 'rails_helper'

RSpec.describe JrcRelationship::ReviewedPortfolioBatch do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:service) { described_class.new(JrcRelationship::Context.new(member)) }
  let(:companies) { Array.new(50) { |index| account.master_companies.create!(name: "Synthetic bounded master scale #{index}") } }
  let(:groups) do
    Array.new(2) { |index| JrcRelationship::PortfolioGroup.create!(account: account, owner: actor, name: "Synthetic scale product #{index}") }
  end
  let(:limit) { { 'user_id' => actor.id, 'unit' => 'hours', 'maximum' => 75, 'availability' => 1, 'dedication' => 1 } }
  let(:foreign) do
    foreign_account = create(:account)
    foreign_actor = create(:user, account: foreign_account, role: :administrator)
    JrcRelationship::Assignment.create!(account: foreign_account, owner: foreign_actor,
                                        contact: create(:contact, account: foreign_account))
  end
  let(:proposal) do
    { 'operation' => 'master_allocation', 'ids' => companies.map(&:id),
      'portfolio_group_id' => groups.first.id, 'expected_version' => 0,
      'justification' => 'Synthetic bounded maximum-audience native hours review', 'request_id' => SecureRandom.uuid,
      'creations' => companies.map do |company|
        { 'company_id' => company.id, 'owner_id' => actor.id, 'settings' => { 'capacity_workload' => { 'hours' => 1.5 } } }
      end }
  end

  before do
    account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm')
    JrcRelationship::Configuration.create!(account: account, rules: {
                                             'handoff_acceptance_required' => true, 'portfolio_capacity_limits' => [limit]
                                           })
    groups.each do |group|
      JrcRelationship::Configuration.create!(account: account, scope_key: "portfolio:#{group.id}", rules: { 'portfolio_capacity_limits' => [limit] })
    end
  end

  it 'creates fifty native roots in finite batches, then reuses all fifty in another active portfolio without doubling global hours' do
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    foreign_digest = JrcRelationship::PlaybookFlowReference.digest(foreign.attributes)
    initial = proposal
    extra = account.master_companies.create!(name: 'Synthetic bounded fifty-first company')
    expect { service.preview(initial.merge('ids' => initial.fetch('ids') + [extra.id])) }.to raise_error(ArgumentError)
    measurements = []
    roots_digest = nil
    groups.each_with_index do |group, phase|
      phase_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      input = initial.merge('portfolio_group_id' => group.id, 'request_id' => SecureRandom.uuid,
                            'creations' => phase.zero? ? initial.fetch('creations') : [])
      preview = service.preview(input)
      expected = { 'create_count' => phase.zero? ? 50 : 0, 'reuse_count' => phase.zero? ? 0 : 50 }
      expect(preview.fetch('summary')).to include(expected)
      expect(preview.fetch('master_capacity').fetch('rows').map { |row| row.slice('unit', 'projected', 'blocker') }.uniq)
        .to eq([{ 'unit' => 'hours', 'projected' => 75.0, 'blocker' => nil }])
      original = JrcRelationship::BatchReview.find(preview.fetch('id'))
      pinned = JrcRelationship::PlaybookFlowReference.digest(original.attributes.slice('inputs', 'snapshot', 'digest', 'account_id', 'actor_id'))
      service.approve(preview.fetch('id'), digest: preview.fetch('digest'))
      result = nil
      10.times do |step|
        result = service.advance(preview.fetch('id'))
        completed = (step + 1) * 5
        state = completed == 50 ? 'completed' : 'running'
        expect([result.fetch('state'), result.fetch('items').count { |item| item.fetch('state') == 'applied' },
                group.customer_links.where(active: true).count, JrcRelationship::Assignment.where(account: account).count])
          .to eq([state, completed, completed, phase.zero? ? completed : 50])
      end
      current = JrcRelationship::PlaybookFlowReference.digest(original.reload.attributes.slice('inputs', 'snapshot', 'digest', 'account_id',
                                                                                               'actor_id'))
      root_rows = JrcRelationship::Assignment.where(account: account).order(:id).map(&:attributes)
      current_roots = JrcRelationship::PlaybookFlowReference.digest(root_rows)
      roots_digest ||= current_roots
      expect([service.advance(preview.fetch('id')), current, current_roots, root_rows.pluck('status').uniq])
        .to eq([result, pinned, roots_digest, ['onboarding']])
      measurements << { phase: phase, created: expected.fetch('create_count'), reused: expected.fetch('reuse_count'),
                        items: result.fetch('items').size, finite_advances: 10,
                        seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - phase_started }
    end
    expect([account.master_companies.count, JrcRelationship::Assignment.where(account: account).count,
            JrcRelationship::CapacityWorkload.sum(JrcRelationship::Assignment.where(account: account), 'hours').to_f,
            groups.map { |group| group.customer_links.where(active: true).count },
            JrcRelationship::PlaybookFlowReference.digest(foreign.reload.attributes)])
      .to eq([51, 50, 75.0, [50, 50], foreign_digest])
    evidence = { database: ActiveRecord::Base.connection.select_value('SELECT current_database()'), phases: measurements,
                 seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started,
                 real_queue: false, external_operations: false, application_build: false }
    path = "/tmp/jrc-master-scale-20261107-#{Process.pid}-#{SecureRandom.hex(6)}.json"
    File.write(path, JSON.pretty_generate(evidence))
    puts({ event: 'master_scale_evidence', artifact: path, seconds: evidence.fetch(:seconds) }.to_json)
  end
end
