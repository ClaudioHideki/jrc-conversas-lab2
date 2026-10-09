require 'rails_helper'

RSpec.describe 'HelpDesk native CRM appointments', type: :request do
  include_context 'NICO HelpDesk native action chain'

  %w[R03 R08].each do |rule|
    context "with actual source #{rule}" do
      let(:selected_rule) { rule }

      it 'prepares, approves and reads the exact customer CRM activity once without an invitation' do
        event
        input = activity_input
        mail_count = ActionMailer::Base.deliveries.size
        approval = nil
        expect { approval = prepare_native(input, 'create_activity') }.not_to change(JrcCrm::Activity, :count)
        expect(approval.scope.dig('group', 'resources')).to include(['JrcCrm::Lead', lead.id], ['JrcNico::ServiceTicketCustomer', ticket.id])
        expect { approve_native(approval) }.to change(JrcCrm::Activity, :count).by(1)
        command = approved_action(approval)
        activity = JrcCrm::Activity.find(command.result.dig('record', 'id'))
        expect(activity).to have_attributes(account_id: sd_account.id, user_id: sd_user.id, lead_id: lead.id,
                                             contact_id: sd_contact.id, company_id: company.id, title: input.dig('activity', 'title'),
                                             activity_type: rule == 'R03' ? 'meeting' : 'follow_up',
                                             due_at: Time.iso8601(input.dig('activity', 'due_at')))
        expect(activity.description).to include("source event #{event.id}", "ticket #{ticket.id}", "Unit #{sd_unit.id}")
        expect(command.result).not_to have_key('browser_action')
        get "/api/v1/accounts/#{sd_account.id}/crm/activities/#{activity.id}", headers: headers
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(input.dig('activity', 'title'))
        expect { approve_native(approval) }.not_to change(JrcCrm::Activity, :count)
        expect(response).to have_http_status(:ok)
        sd_account.disable_features!('jrc_crm')
        verify_receipt_hidden(approval)
        expect(activity.reload).to be_persisted
        expect(ActionMailer::Base.deliveries.size).to eq(mail_count)
        expect(a_request(:any, %r{https?://})).not_to have_been_made
      end
    end
  end

  it 'rejects a CRM record from another customer before creating a pending command' do
    foreign_contact = create(:contact, account: sd_account)
    foreign = JrcCrm::Lead.create!(account: sd_account, owner: sd_user, contact: foreign_contact, name: 'Other customer')
    input = activity_input.deep_merge('activity' => { 'lead_id' => foreign.id })
    post "#{base}/group_preview", params: { event_id: event.id, group_key: selected_group, input: input }, headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(JrcNico::Helpdesk::Approval.where(account: sd_account)).to be_empty
    expect(JrcCrm::Activity.where(account: sd_account)).to be_empty
  end

  it 'rejects a CRM record from another account even for an administrator' do
    foreign_user = create(:user, account: sd_foreign_account)
    foreign = JrcCrm::Lead.create!(account: sd_foreign_account, owner: foreign_user, name: 'Foreign tenant')
    input = activity_input.deep_merge('activity' => { 'lead_id' => foreign.id })
    post "#{base}/group_preview", params: { event_id: event.id, group_key: selected_group, input: input }, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    expect(JrcNico::Helpdesk::Approval.where(account: sd_account)).to be_empty
  end

  it 'requires a single explicit CRM identity and an ISO time with offset and rejects forged types' do
    [activity_input.deep_merge('activity' => { 'deal_id' => lead.id }),
     { 'activity' => activity_input.fetch('activity').except('lead_id') },
     activity_input.deep_merge('activity' => { 'due_at' => '2026-10-09T12:00:00' }),
     activity_input.deep_merge('activity' => { 'lead_id' => lead.id.to_s }),
     activity_input.deep_merge('activity' => { 'activity_type' => 'call' }),
     activity_input.deep_merge('activity' => { 'description' => nil }),
     activity_input.deep_merge('activity' => { 'description' => 123 })].each do |input|
      post "#{base}/group_preview", params: { event_id: event.id, group_key: selected_group, input: input }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'HELPDESK_INVALID_REQUEST')
    end
    expect(JrcNico::Helpdesk::Approval.where(account: sd_account)).to be_empty
  end

  it 'rechecks CRM permission before approval without losing the pending record or creating an activity' do
    approval = prepare_native(activity_input, 'create_activity')
    sd_account.disable_features!('jrc_crm')
    expect { approve_native(approval) }.not_to change(JrcCrm::Activity, :count)
    expect(response).to have_http_status(:unauthorized)
    expect(approval.reload.state).to eq('pending')
    verify_receipt_hidden(approval)
  end

  it 'rejects native customer identity drift after preparing the exact CRM source' do
    approval = prepare_native(activity_input, 'create_activity')
    other_contact = create(:contact, account: sd_account, company_id: company.id)
    lead.update!(contact: other_contact)
    expect { approve_native(approval) }.not_to change(JrcCrm::Activity, :count)
    expect(response).to have_http_status(:unauthorized)
    expect(approval.reload.state).to eq('pending')
    verify_receipt_hidden(approval)
  end

  it 'rejects expiry before native execution and preserves the exact prepared arguments' do
    approval = prepare_native(activity_input, 'create_activity')
    arguments = approval.command.arguments
    travel_to(approval.expires_at + 1)
    expect { approve_native(approval) }.not_to change(JrcCrm::Activity, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(approval.reload.state).to eq('pending')
    expect(approval.command.reload.arguments).to eq(arguments)
  end

  it 'cannot prepare from another original actor even when the second operator is an administrator' do
    captured = event
    other_user = create(:user, account: sd_account, role: :administrator)
    other_member = sd_account.account_users.find_by!(user: other_user)
    create(:jrc_sd_membership, unit: sd_unit, account_user: other_member)
    post "#{base}/group_preview", params: { event_id: captured.id, group_key: selected_group, input: activity_input },
                                  headers: other_user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(JrcCrm::Activity.where(account: sd_account)).to be_empty
    expect(JrcNico::Helpdesk::Approval.where(account: sd_account)).to be_empty
  end

  it 'rechecks the originating Unit membership before approval even for the original administrator' do
    approval = prepare_native(activity_input, 'create_activity')
    sd_membership.update!(active: false)
    expect { approve_native(approval) }.not_to change(JrcCrm::Activity, :count)
    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body).to eq('error' => 'Resource could not be found')
    expect(approval.reload.state).to eq('pending')
  end
end
