require 'rails_helper'

RSpec.describe 'Task read query scaling', type: :request do
  let(:page_sizes) { [1, 25] }

  %w[administrator member contributor].each do |role|
    it "bounds SELECT growth for #{role} reads across one and twenty-five tasks" do
      account = create(:account)
      account.enable_features!('jrc_projects')
      admin = create(:user, account: account, role: :administrator)
      actor = role == 'administrator' ? admin : create(:user, account: account, role: :agent)
      account.account_users.find_by!(user: actor).update!(jrc_projects_enabled: true)
      project = JrcProjects::Projects::Create.call(account: account, actor: admin, attributes: { name: 'Synthetic task read' },
                                                   idempotency_key: SecureRandom.uuid)
      project.project_members.create!(account: account, user: actor, role: role) unless role == 'administrator'
      column = project.board_columns.find_by!(status_key: 'backlog')
      25.times do |index|
        project.tasks.create!(account: account, created_by: admin, assignee: index.even? ? actor : nil,
                              board_column: column, title: "Synthetic #{index}", status: 'backlog')
      end
      headers = actor.create_new_auth_token
      url = "/api/v1/accounts/#{account.id}/projects/projects/#{project.id}/tasks"
      get url, params: { per_page: 1 }, headers: headers
      measurements = page_sizes.map do |size|
        queries = []
        subscriber = lambda { |*args|
          payload = args.last
          queries << payload[:sql] if payload[:sql].match?(/\ASELECT/i)
        }
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        ActiveRecord::Base.uncached do
          ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') do
            get url, params: { per_page: size }, headers: headers
          end
        end
        expect(response).to have_http_status(:ok)
        rows = response.parsed_body.fetch('data')
        expect(rows.size).to eq(size)
        expect(rows).to all(include('can_move' => (role != 'contributor'), 'can_delete' => (role == 'administrator')))
        expected_updates = rows.map { |row| role != 'contributor' || row.fetch('assignee_id') == actor.id }
        expect(rows.pluck('can_update')).to eq(expected_updates)
        elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(1)
        warn "task_read_request role=#{role} tasks=#{size} selects=#{queries.size} elapsed_ms=#{elapsed}"
        queries.size
      end
      expect(measurements.max - measurements.min).to be <= 2
      account.account_users.find_by!(user: actor).destroy!
      get url, headers: headers
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
