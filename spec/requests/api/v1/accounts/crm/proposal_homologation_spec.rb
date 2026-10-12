require 'rails_helper'

RSpec.describe 'CRM proposal homologation regressions', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:headers) { agent.create_new_auth_token }
  let(:company) { account.master_companies.create!(name: 'Nexora homologação', trade_name: 'Nexora Tech', tax_id: '11222333000181') }
  let(:contact) { create(:contact, account: account, company_id: company.id, name: 'Thiago homologação', email: 'thiago@example.com') }
  let(:pipeline) { JrcCrm::DefaultPipelineService.new(account).perform }
  let(:deal) { JrcCrm::Deal.create!(account: account, pipeline: pipeline, stage: pipeline.stages.active.order(:position).first,
                                  owner: agent, company: company, contact: contact, title: 'Negócio real') }
  let(:product) { JrcCrm::Product.create!(account: account, name: 'Serviço CRM', sku: 'HML-01', unit_price_cents: 20_000, active: true) }
  let(:proposal) { JrcCrm::ProposalBuilderService.new(actor: agent, account: account, company: company, contact: contact).call }
  let(:url) { "/api/v1/accounts/#{account.id}/crm/proposals" }
  let(:public_url) { "/api/v1/accounts/#{account.id}/crm/public/proposals/#{proposal.public_token}" }
  let(:html_url) { "/jrc/propostas/#{account.id}/#{proposal.public_token}" }
  let(:signer) { { accepted_by_name: 'Thiago Ribeiro', accepted_by_document: 'synthetic-signer-document' } }
  before { account.enable_features!('jrc_crm', 'jrc_customer_master') }

  # Exercise the real send endpoint and delivery/audit service, with test jobs and storage.
  # Reused by the two conversion regressions and the valid public acceptance case.
  def deliver_proposal
    proposal.proposal_items.create!(product: product, name_snapshot: product.name, quantity: 2,
                                    unit_price_cents: product.unit_price_cents, billing_model: product.billing_model)
    conversation = create(:conversation, account: account, contact: contact)
    post "#{url}/#{proposal.id}/send_proposal", headers: headers, as: :json
    expect(response).to have_http_status(:ok), response.body.first(600)
    expect(proposal.reload.status).to eq('sent')
    expect(proposal.sent_at).to be_present
    event = proposal.events.find_by!(event_type: 'sent')
    expect(event.user_id).to eq(agent.id)
    expect(event.metadata).to include('conversation_id' => conversation.id, 'message_id' => proposal.last_sent_message_id)
    message = conversation.messages.find(proposal.last_sent_message_id)
    expect(message.attachments.count).to eq(1)
    expect(message.attachments.first.file.download).to start_with('%PDF-')
    expect(message.attachments.first.file.content_type).to eq('application/pdf')
  end

  it 'PROP-01 copies the existing real deal and its products without replacing the customer' do
    deal.deal_products.create!(product: product, quantity: 2, unit_price_cents: 20_000, discount_cents: 0)
    post url, params: { deal_id: deal.id }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    expect(response.parsed_body['deal_id']).to eq(deal.id)
    expect(response.parsed_body.dig('customer', 'id')).to eq(contact.id)
    expect(response.parsed_body['items_count']).to eq(1)
    expect(response.parsed_body['total_cents']).to eq(40_000)
  end

  it 'PROP-02 creates directly against the master company/contact with items and no artificial deal' do
    expect {
      post url, params: { company_id: company.id, contact_id: contact.id,
                         proposal: { title: 'Proposta direta', commercial_notes: 'Condição negociada' },
                         items: [{ product_id: product.id, quantity: 2, unit_price_cents: 20_000, discount_cents: 0 }] },
                headers: headers, as: :json
    }.not_to change(JrcCrm::Deal, :count)
    expect(response).to have_http_status(:created)
    expect(response.parsed_body['deal_id']).to be_nil
    expect(response.parsed_body.dig('company', 'id')).to eq(company.id)
    expect(response.parsed_body.dig('customer', 'id')).to eq(contact.id)
    expect(response.parsed_body['total_cents']).to eq(40_000)
  end

  it 'PROP-03/04 searches the same newly created master identity by name, trade name, tax id and contact' do
    company
    contact
    ['Nexora homologação', 'Nexora Tech', '11.222.333/0001-81', 'thiago@example.com'].each do |query|
      get "/api/v1/accounts/#{account.id}/customers/companies", params: { q: query, per_page: 15 }, headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['payload'].pluck('id')).to eq([company.id])
    end
  end

  it 'PROP-05/06 renders the public proposal repeatedly with one canonical audit per view' do
    proposal.update!(status: 'sent', sent_at: Time.current)
    token = proposal.public_token
    2.times do
      expect { get "/jrc/propostas/#{account.id}/#{token}" }.to change(JrcCrm::ProposalEvent, :count).by(1)
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('text/html')
      expect(response.body).to include(company.name)
      expect(response.body).not_to include('Event type is not included')
    end
    expect(proposal.reload.status).to eq('viewed')
    expect(proposal.viewed_count).to eq(2)
    expect(proposal.events.where(event_type: 'viewed').count).to eq(2)
    expect(proposal.events.order(:id).last.metadata).to include('view_number' => 2, 'repeated' => true)
  end

  it 'audits the public JSON view endpoint with the same valid event' do
    proposal.update!(status: 'sent', sent_at: Time.current)
    token = proposal.public_token
    2.times do
      post "/api/v1/accounts/#{account.id}/crm/public/proposals/#{token}/view", as: :json
      expect(response).to have_http_status(:ok)
    end
    expect(proposal.reload.viewed_count).to eq(2)
    expect(proposal.events.where(event_type: 'viewed').count).to eq(2)
  end

  it 'CRM-PROP-001/004 hides pre-send content without counting a public view or allowing a PDF' do
    %w[draft pending_approval].each do |state|
      proposal.update!(status: state)
      expect { get "/jrc/propostas/#{account.id}/#{proposal.public_token}" }.not_to change { proposal.reload.viewed_count }
      expect(response.body).to include('ainda não foi enviada')
      expect(response.body).not_to include(company.name)
      get "/jrc/propostas/#{account.id}/#{proposal.public_token}/pdf"
      expect(response).to have_http_status(:unprocessable_entity)
      post "/api/v1/accounts/#{account.id}/crm/public/proposals/#{proposal.public_token}/view", as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
    proposal.update!(status: 'draft', approval_status: 'approved')
    get "/jrc/propostas/#{account.id}/#{proposal.public_token}"
    expect(response.body).to include('aguardando envio')
    expect(proposal.reload.viewed_count).to eq(0)
  end

  it 'CRM-PROP-005 protects direct model transitions and preserves the state across repeated views' do
    %w[viewed accepted rejected].each do |state|
      expect { proposal.update!(status: state, sent_at: Time.current) }.to raise_error(ActiveRecord::RecordInvalid)
      proposal.reload
    end
    proposal.update!(status: 'sent', sent_at: Time.current)
    2.times { proposal.record_customer_view! }
    expect(proposal.reload.status).to eq('viewed')
    expect(proposal.viewed_count).to eq(2)
  end

  it 'shows expiration without exposing customer data and records the expiration only once' do
    proposal.update!(status: 'sent', sent_at: Time.current, valid_until: Date.current - 1)
    2.times do
      get "/jrc/propostas/#{account.id}/#{proposal.public_token}"
      expect(response.body).to include('expirou')
      expect(response.body).not_to include(company.name)
    end
    expect(proposal.events.where(event_type: 'expired').count).to eq(1)
    expect(proposal.reload.viewed_count).to eq(0)
  end

  it 'PROP-07 rejects cross-account and invalid public tokens without modifying either proposal' do
    other = create(:account)
    other.enable_features!('jrc_crm')
    get "/api/v1/accounts/#{other.id}/crm/public/proposals/#{proposal.public_token}", as: :json
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(company.name)
    %w[view accept reject].each do |action|
      post "/api/v1/accounts/#{other.id}/crm/public/proposals/#{proposal.public_token}/#{action}", params: signer, as: :json
      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include(company.name, contact.email)
    end
    get "/api/v1/accounts/#{account.id}/crm/public/proposals/invalid-token", as: :json
    expect(response).to have_http_status(:not_found)
    expect(proposal.reload.viewed_count).to eq(0)
  end

  %w[expired revoked].each do |state|
    context "with a #{state} public token" do
      around { |example| travel_to(Time.zone.local(2026, 10, 12, 12)) { example.run } }
      before do
        proposal.update!(status: 'sent', sent_at: Time.current)
        proposal.update!(state == 'expired' ? { public_token_expires_at: Time.current } : { public_token_revoked_at: Time.current })
      end

      it 'returns only unavailable JSON and blocks public data, PDF and response actions' do
        get public_url, as: :json
        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq('application/json')
        expect(response.parsed_body).to eq('availability' => {
          'state' => state == 'expired' ? 'expired' : 'canceled', 'available' => false,
          'message' => JrcCrm::ProposalPublicState::MESSAGES.fetch(state == 'expired' ? 'expired' : 'canceled')
        })
        get html_url
        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include(company.name, contact.email, proposal.title, proposal.proposal_number)
        get "#{html_url}/pdf"
        expect(response).to have_http_status(:unprocessable_entity)
        %w[view accept reject].each do |action|
          post "#{public_url}/#{action}", params: signer, as: :json
          expect(response).to have_http_status(:unprocessable_entity)
          expect(response.body).not_to include(company.name, contact.email, proposal.title, proposal.proposal_number)
        end
        expect(proposal.reload.status).to eq('sent')
        expect(proposal.viewed_count).to eq(0)
        expect(proposal.sales_orders.count).to eq(0)
        expect(proposal.events.where(event_type: %w[viewed accepted rejected]).count).to eq(0)
        expect(proposal.events.where(event_type: 'expired').count).to eq(state == 'expired' ? 1 : 0)
      end

      it 'keeps protected content out of HTML acceptance errors with or without signer fields' do
        [{}, signer].each do |fields|
          post "#{html_url}/accept", params: fields
          expect(response).to have_http_status(:unprocessable_entity)
          expect(response.media_type).to eq('text/html')
          expect(response.body).not_to include(company.name, contact.email, proposal.title, proposal.proposal_number)
        end
        post "#{html_url}/reject", params: { reason: 'Synthetic reason' }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).not_to include(company.name, contact.email, proposal.title, proposal.proposal_number)
        expect(proposal.reload.status).to eq('sent')
        expect(proposal.sales_orders.count).to eq(0)
        expect(proposal.events.where(event_type: %w[accepted rejected]).count).to eq(0)
      end

      it 'blocks replay of acceptance and conversion after an already accepted token becomes unavailable' do
        proposal.update!(public_token_expires_at: 1.day.from_now, public_token_revoked_at: nil)
        proposal.accept_by_customer!(name: signer[:accepted_by_name], document: signer[:accepted_by_document],
                                     remote_ip: '127.0.0.1', user_agent: 'native test')
        proposal.update!(state == 'expired' ? { public_token_expires_at: Time.current } : { public_token_revoked_at: Time.current })
        %w[accept reject view].each do |action|
          post "#{public_url}/#{action}", params: signer, as: :json
          expect(response).to have_http_status(:unprocessable_entity)
          expect(response.body).not_to include(company.name, contact.email, proposal.proposal_number)
        end
        post "#{html_url}/accept", params: signer
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).not_to include(company.name, contact.email, proposal.title)
        expect(proposal.reload.status).to eq('accepted')
        expect(proposal.sales_orders.count).to eq(0)
        expect(account.jrc_crm_audit_events.where(event_type: 'order_created').count).to eq(0)
      end
    end
  end

  it 'blocks every public JSON action for an invalid token' do
    proposal
    invalid_url = "/api/v1/accounts/#{account.id}/crm/public/proposals/invalid-token"
    %w[view accept reject].each do |action|
      post "#{invalid_url}/#{action}", params: signer, as: :json
      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include(company.name, contact.email)
    end
    expect(proposal.reload.status).to eq('draft')
    expect(proposal.sales_orders.count).to eq(0)
    expect(proposal.events.pluck(:event_type)).to eq(['created'])
  end

  it 'accepts a valid officially sent public proposal once and preserves conversion on replay' do
    deliver_proposal
    get public_url, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('company', 'id')).to eq(company.id)
    expect(response.parsed_body.dig('customer', 'email')).to eq(contact.email)
    expect(response.parsed_body['items'].size).to eq(1)
    post "#{public_url}/view", as: :json
    expect(response).to have_http_status(:ok)
    post "#{public_url}/accept", params: signer, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['success']).to be(true)
    first_id = response.parsed_body.dig('sales_order', 'id')
    expect(first_id).to be_present
    post "#{public_url}/accept", params: signer, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('sales_order', 'id')).to eq(first_id)
    expect(proposal.reload.status).to eq('accepted')
    expect(proposal.sales_orders.count).to eq(1)
    expect(proposal.events.where(event_type: 'accepted').count).to eq(1)
    expect(account.jrc_crm_audit_events.where(event_type: 'order_created').count).to eq(1)
    expect(proposal.sales_orders.first.total_cents).to eq(proposal.total_cents)
  end

  %w[draft pending_approval sent].each do |state|
    it "blocks acceptance and conversion of #{state} without an official send timestamp" do
      proposal.update!(status: state)
      expect(proposal.sent_at).to be_nil
      expect { proposal.accept_by_customer!(name: signer[:accepted_by_name], document: signer[:accepted_by_document],
                                             remote_ip: '127.0.0.1', user_agent: 'native test') }.to raise_error(ActiveRecord::RecordInvalid)
      proposal.reload
      post "#{public_url}/accept", params: signer, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      post "#{url}/#{proposal.id}/convert_to_order", headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      post "#{html_url}/accept", params: {}
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).not_to include(company.name, contact.email, proposal.title)
      expect(proposal.reload.status).to eq(state)
      expect(proposal.sales_orders.count).to eq(0)
    end
  end

  it 'PROP-08 deletes an unlinked editable proposal while retaining an independent audit' do
    id = proposal.id
    delete "#{url}/#{id}", headers: headers, as: :json
    expect(response).to have_http_status(:no_content)
    expect(JrcCrm::Proposal.exists?(id)).to be(false)
    audit = JrcCrm::AuditEvent.find_by!(account: account, resource_type: 'JrcCrm::Proposal', resource_id: id, event_type: 'proposal_deleted')
    expect(audit.actor_id).to eq(agent.id)
    expect(audit.from_value['company_id']).to eq(company.id)
    expect(audit.from_value).not_to have_key('public_token_digest')
  end

  it 'PROP-09 preserves the proposal, order and contract when deletion is blocked' do
    deliver_proposal
    proposal.accept_by_customer!(name: 'Thiago Ribeiro', document: 'signer-document', remote_ip: '127.0.0.1', user_agent: 'native test')
    order = JrcCrm::ProposalToOrderService.new(proposal: proposal, actor: agent).call
    delete "#{url}/#{proposal.id}", headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcCrm::Proposal.exists?(proposal.id)).to be(true)
    expect(order.reload.proposal_id).to eq(proposal.id)
  end

  it 'ACCOUNT-01 rejects company/contact from another account and a contact from another company' do
    outsider = create(:contact)
    post url, params: { company_id: company.id, contact_id: outsider.id }, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    unrelated = create(:contact, account: account)
    post url, params: { company_id: company.id, contact_id: unrelated.id }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['errors'].join).to include('empresa selecionada')
  end

  it 'preserves identity, accepted values and idempotency when a direct proposal becomes an order' do
    deliver_proposal
    proposal.accept_by_customer!(name: 'Thiago Ribeiro', document: 'signer-document', remote_ip: '127.0.0.1', user_agent: 'native test')
    first = JrcCrm::ProposalToOrderService.new(proposal: proposal, actor: agent).call
    second = JrcCrm::ProposalToOrderService.new(proposal: proposal, actor: agent).call
    expect(first.id).to eq(second.id)
    expect(first.deal_id).to be_nil
    expect(first.contact_id).to eq(contact.id)
    expect(first.snapshot['company_id']).to eq(company.id)
    expect(first.total_cents).to eq(proposal.total_cents)
  end

  it 'duplicates a direct proposal using a permitted audit event and fresh public token' do
    post "#{url}/#{proposal.id}/duplicate", headers: headers, as: :json
    expect(response).to have_http_status(:created)
    duplicate = JrcCrm::Proposal.find(response.parsed_body['id'])
    expect(duplicate.company_id).to eq(company.id)
    expect(duplicate.contact_id).to eq(contact.id)
    expect(duplicate.public_token_digest).not_to eq(proposal.public_token_digest)
    expect(duplicate.events.last.event_type).to eq('duplicated')
  end

  it 'prevents another owner from deleting an account proposal' do
    other_agent = create(:user, account: account, role: :agent)
    delete "#{url}/#{proposal.id}", headers: other_agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
    expect(proposal.reload).to be_present
  end
end
