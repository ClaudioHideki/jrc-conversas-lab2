require 'rails_helper'
require 'timeout'

RSpec.describe 'Concurrent rich comment publication', type: :request do
  self.use_transactional_tests = false
  around do |example|
    if Rails.env.test? && ENV['JRC_PROJECT_COMMENT_CONCURRENCY'] == '1' &&
       ActiveRecord::Base.connection.current_database == 'jrc_four_fronts_concurrency_20261026_test'
      example.run
    else
      skip 'Requires the dedicated, committed synthetic concurrency database'
    end
  end

  it 'uses two PostgreSQL connections and commits exactly one comment for racing identical requests' do
    account = create(:account, name: 'JRC four-fronts synthetic concurrency')
    user = create(:user, account: account, role: :administrator)
    account.enable_features!('jrc_projects')
    project = JrcProjects::Projects::Create.call(account: account, actor: user, attributes: { name: 'Synthetic concurrent project' }, idempotency_key: SecureRandom.uuid)
    task = project.tasks.create!(account: account, created_by: user, board_column: project.board_columns.first!, status: 'backlog', title: 'Synthetic concurrent task')
    headers = user.create_new_auth_token.merge('Idempotency-Key' => 'synthetic-concurrent-comment-0001')
    url = "/api/v1/accounts/#{account.id}/projects/projects/#{project.id}/tasks/#{task.id}/comments"
    expect(ActiveRecord::Base.connection.transaction_open?).to be(false)
    gate = Queue.new
    results = Queue.new
    workers = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          pid = connection.select_value('SELECT pg_backend_pid()')
          gate.pop
          client = ActionDispatch::Integration::Session.new(Rails.application)
          client.post(url, headers: headers, params: { comment: { body: '**One synthetic comment**', content_format: 'markdown' } }, as: :json)
          results << { http: client.response.status, id: client.response.parsed_body.dig('data', 'id'), pid: pid }
        rescue StandardError => error
          results << error
        end
      end
    end
    2.times { gate << true }
    Timeout.timeout(30) { workers.each(&:join) }
    outcomes = 2.times.map { results.pop }
    expect(outcomes).to all(be_a(Hash))
    expect(outcomes.pluck(:pid).uniq.length).to eq(2)
    expect(outcomes.pluck(:http).sort).to eq([200, 201])
    expect(outcomes.pluck(:id).uniq).to eq([task.task_comments.sole.id])
    expect(JrcProjects::AuditEvent.where(account: account, action: 'projects.task.comment_added').count).to eq(1)
    puts 'COMMENT_CONCURRENCY_PROOF ' + outcomes.to_json
  ensure
    workers&.each { |worker| worker.kill if worker.alive? }
    workers&.each(&:join)
  end
end
