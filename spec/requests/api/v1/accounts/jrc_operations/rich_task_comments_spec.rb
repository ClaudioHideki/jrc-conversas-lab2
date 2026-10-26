require 'rails_helper'

RSpec.describe 'Rich project task comments', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }
  let(:project) { JrcProjects::Projects::Create.call(account: account, actor: admin, attributes: { name: 'Synthetic comments' }, idempotency_key: SecureRandom.uuid) }
  let(:task) { project.tasks.create!(account: account, created_by: admin, board_column: project.board_columns.first!, status: 'backlog', title: 'Synthetic task') }
  let(:base) { "/api/v1/accounts/#{account.id}/projects/projects/#{project.id}/tasks/#{task.id}" }
  let(:image_key) { 'synthetic-image-00000001' }
  let(:body) { "**Before**\n\n![Print](comment-image:#{image_key})\n\nAfter *image*." }
  let(:upload) { fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png') }
  let(:payload) { { comment: { body: body, content_format: 'markdown', images: { image_key => upload } } } }

  before { account.enable_features!('jrc_projects') }

  it 'persists ordered rich text and private images exclusively on the comment' do
    post "#{base}/comments", params: payload, headers: headers
    expect(response).to have_http_status(:created), response.body
    record = JrcProjects::TaskComment.last
    expect(record.body).to eq(body)
    expect(record.content_format).to eq('markdown')
    expect(record.inline_images.count).to eq(1)
    expect(task.attachments.count).to eq(0)
    data = response.parsed_body.fetch('data')
    expect(data.fetch('inline_images').first).to include('key' => image_key, 'content_type' => 'image/png')
    expect(data.to_json).not_to match(/signed_id|rails\/active_storage|request_digest/)
    get "#{base}/files", headers: headers
    expect(response.parsed_body.fetch('data')).to eq([])
    get base, headers: headers
    expect(response.parsed_body.dig('data', 'comments').first).to include('body' => body, 'content_format' => 'markdown')
  end

  it 'downloads only through the authorized Account/project/task/comment endpoint' do
    post "#{base}/comments", params: payload, headers: headers
    record = JrcProjects::TaskComment.last
    image = record.inline_images.attachments.first!
    get "#{base}/comments/#{record.id}/images/#{image.id}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('image/png')
    expect(response.headers['Cache-Control']).to include('private', 'no-store')
    expect(response.headers['X-Content-Type-Options']).to eq('nosniff')
    expect(response.body.b).to eq(File.binread(Rails.root.join('spec/assets/avatar.png')))
    get "#{base}/comments/#{record.id}/images/#{image.id}"
    expect(response).to have_http_status(:unauthorized)
  end

  it 'rejects access through a different task even within the same project' do
    post "#{base}/comments", params: payload, headers: headers
    record = JrcProjects::TaskComment.last
    another = project.tasks.create!(account: account, created_by: admin, board_column: project.board_columns.first!, status: 'backlog', title: 'Other task')
    get "#{base.sub("/tasks/#{task.id}", "/tasks/#{another.id}")}/comments/#{record.id}/images/#{record.inline_images.attachments.first.id}", headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it 'rejects another Account and a user without project membership' do
    post "#{base}/comments", params: payload, headers: headers
    record = JrcProjects::TaskComment.last
    image_path = "#{base}/comments/#{record.id}/images/#{record.inline_images.attachments.first.id}"
    foreign_account = create(:account)
    foreign_user = create(:user, account: foreign_account, role: :administrator)
    get image_path, headers: foreign_user.create_new_auth_token
    expect(response.status).to be_in([401, 403, 404])
    member = create(:user, account: account, role: :agent)
    account.account_users.find_by!(user: member).update!(jrc_projects_enabled: true)
    get image_path, headers: member.create_new_auth_token
    expect(response.status).to be_in([403, 404])
  end

  it 'cannot reuse another comment image or point to an external/base64 image' do
    post "#{base}/comments", params: payload, headers: headers
    original_count = JrcProjects::TaskComment.count
    [body, '![Outside](https://invalid.example/image.png)', '![Data](data:image/png;base64,AAAA)'].each do |invalid_body|
      post "#{base}/comments", params: { comment: { body: invalid_body, content_format: 'markdown' } }, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
    expect(JrcProjects::TaskComment.count).to eq(original_count)
  end

  it 'rejects files that are not images even when their content type claims PNG' do
    bad = fixture_file_upload(Rails.root.join('spec/fixtures/files/jrc_projects_task.txt'), 'image/png')
    expect do
      post "#{base}/comments", params: { comment: { body: body, content_format: 'markdown', images: { image_key => bad } } }, headers: headers
    end.not_to change(JrcProjects::TaskComment, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'keeps one comment and audit event after retrying the same acknowledged upload' do
    task
    retry_headers = headers.merge('Idempotency-Key' => 'synthetic-comment-00000001')
    expect do
      2.times { post "#{base}/comments", params: payload, headers: retry_headers }
    end.to change(JrcProjects::TaskComment, :count).by(1)
    expect(response).to have_http_status(:ok)
    expect(JrcProjects::AuditEvent.where(account: account, action: 'projects.task.comment_added').count).to eq(1)
    post "#{base}/comments", params: { comment: { body: 'Changed', content_format: 'markdown' } }, headers: retry_headers
    expect(response).to have_http_status(:conflict)
    expect(JrcProjects::TaskComment.last.body).to eq(body)
  end

  it 'updates text while retaining image ownership and blocks a viewer mutation' do
    post "#{base}/comments", params: payload, headers: headers
    record = JrcProjects::TaskComment.last
    patch "#{base}/comments/#{record.id}", params: { comment: { body: body + "\n\nNew ending", content_format: 'markdown' } }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(record.reload.body).to end_with('New ending')
    viewer = create(:user, account: account, role: :agent)
    account.account_users.find_by!(user: viewer).update!(jrc_projects_enabled: true)
    project.project_members.create!(account: account, user: viewer, role: 'viewer')
    expect do
      patch "#{base}/comments/#{record.id}", params: { comment: { body: 'Forbidden' } }, headers: viewer.create_new_auth_token
    end.not_to(change { record.reload.body })
    expect(response).to have_http_status(:forbidden)
  end

  it 'preserves plain text comments and never interprets historical HTML as rich content' do
    historical = task.task_comments.create!(account: account, user: admin, body: '<b>Historical text</b>')
    get "#{base}/comments", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('data').find { |row| row['id'] == historical.id }).to include(
      'body' => '<b>Historical text</b>', 'content_format' => 'plain_text', 'inline_images' => []
    )
  end
end
