require 'rails_helper'

RSpec.describe 'Campaign sending governance' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:step) { campaign.steps.create!(kind: 'template', position: 0, template_name: 'sample_shipping_confirmation', template_language: 'en_US') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_whatsapp, account: account)) }
  let(:contact) { create(:contact, account: account, phone_number: '+5511999999999') }
  let(:campaign) { JrcCampaigns::Campaign.create!(account: account, inbox: inbox, name: 'Pilot') }

  before do
    stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook')
    stub_request(:get, 'https://waba.360dialog.io/v1/configs/templates').to_return(
      status: 200, headers: { 'Content-Type' => 'application/json' },
      body: { waba_templates: [{ name: 'sample_shipping_confirmation', language: 'en_US', status: 'approved', components: [] }] }.to_json
    )
    step
  end

  it 'rejects the legacy inbox from another account' do
    campaign.inbox = create(:inbox)
    expect(campaign).not_to be_valid
    expect(campaign.errors[:inbox]).to be_present
  end

  it 'rejects launching existing drafts without human approval' do
    expect { campaign.launch! }.to raise_error(ActiveRecord::RecordInvalid)
    expect(campaign.reload).to be_draft
  end

  it 'excludes contacts without recorded positive consent' do
    contact
    expect(JrcCampaigns::AudienceResolver.new(campaign).entries).to be_empty
  end

  context 'with a GoPure email campaign' do
    let(:inbox) { create(:inbox, account: account, channel: create(:channel_email, account: account)) }
    let(:contact) { create(:contact, account: account, email: 'campaign@example.test', phone_number: nil) }
    let(:campaign) { JrcCampaigns::Campaign.create!(account: account, inbox: inbox, created_by: admin, name: 'Email GoPure', delivery_channel: 'email') }
    let(:step) { campaign.steps.create!(kind: 'email', position: 0, subject: 'GoPure', body: 'Olá') }

    it 'approves the email destination and sends once through the existing email sender' do
      contact
      campaign.request_review!
      campaign.approve!(admin, campaign.review_digest)
      execution = JrcCampaigns::LaunchService.new(campaign).perform
      recipient = execution.recipients.sole
      expect(recipient.destination).to eq(contact.email)
      mail_conversation = create(:conversation, account: account, inbox: inbox, contact: contact)
      message = create(:message, account: account, inbox: inbox, conversation: mail_conversation, message_type: :outgoing)
      sender = instance_double(JrcCampaigns::EmailSender)
      allow(JrcCampaigns::EmailSender).to receive(:new).and_return(sender)
      expect(sender).to receive(:perform).once.and_return(external_id: 'qa-mail-id', contact: contact, conversation: mail_conversation, message: message)
      2.times { JrcCampaigns::DispatchStepService.new(recipient: recipient, step: step).perform }
      expect(recipient.reload).to be_sent
      expect(recipient.deliveries.sole.external_id).to eq('qa-mail-id')
    end

    it 'requires a new review after the email subject changes' do
      contact
      campaign.request_review!
      campaign.approve!(admin, campaign.review_digest)
      step.update!(subject: 'Outro assunto')
      expect(campaign.reload.approval_valid?).to be_falsey
    end
  end

  context 'with recorded consent' do
    before do
      JrcCampaigns::Consent.create!(account: account, phone_number: contact.phone_number, evidence: 'Signed form', recorded_by: admin,
                                    granted_at: Time.current)
    end

    it 'freezes the approved recipients when contacts are added before scheduled execution' do
      campaign.request_review!
      campaign.approve!(admin, campaign.review_digest)
      create(:contact, account: account, phone_number: '+5511888888888')
      JrcCampaigns::Consent.create!(account: account, phone_number: '+5511888888888', evidence: 'Later opt-in', recorded_by: admin,
                                    granted_at: Time.current)
      execution = JrcCampaigns::LaunchService.new(campaign).perform
      expect(execution.recipients.pluck(:phone_number)).to eq(['+5511999999999'])
    end

    it 'invalidates approval after a nested sending step changes' do
      campaign.request_review!
      campaign.approve!(admin, campaign.review_digest)
      step.update!(template_language: 'id')
      expect { campaign.reload.launch! }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it 'rejects expired approval at scheduled execution' do
      campaign.request_review!
      campaign.approve!(admin, campaign.review_digest)
      travel 49.hours do
        expect { JrcCampaigns::LaunchService.new(campaign).perform }.to raise_error(ActiveRecord::RecordInvalid)
      end
      expect(campaign.executions).to be_empty
    end

    it 'rejects approval by a regular agent even through the service API' do
      campaign.request_review!
      agent = create(:user, account: account, role: :agent)
      expect { campaign.approve!(agent, campaign.review_digest) }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it 'rejects freeform test sends outside the conversation window despite opt-in' do
      test = JrcCampaigns::TestMessageService.new(account: account, user: admin, phone_number: contact.phone_number,
                                                  inbox_id: inbox.id, step: { kind: 'text', body: 'Hello' })
      expect { test.perform }.to raise_error(ArgumentError, /janela/)
    end

    it 'does not borrow another phone window from a merged contact' do
      old_link = create(:contact_inbox, contact: contact, inbox: inbox, source_id: contact.phone_number.delete_prefix('+'))
      other_link = create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5511888888888')
      old_conversation = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: old_link)
      other_conversation = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: other_link)
      create(:message, account: account, inbox: inbox, conversation: old_conversation, sender: contact, created_at: 25.hours.ago)
      create(:message, account: account, inbox: inbox, conversation: other_conversation, sender: contact)

      policy = JrcCampaigns::EligibilityPolicy.new(account: account, phone_number: contact.phone_number, contact: contact)
      expect { policy.freeform_conversation!(inbox) }.to raise_error(ArgumentError, /janela/)
    end

    context 'with a queued recipient' do
      let(:execution) { campaign.executions.create!(run_number: 1, status: 'running') }
      let(:recipient) do
        execution.recipients.create!(campaign: campaign, inbox: inbox, contact: contact, phone_number: contact.phone_number,
                                     destination: contact.phone_number)
      end
      let(:service) { JrcCampaigns::DispatchStepService.new(recipient: recipient, step: step) }

      before do
        campaign.request_review!
        campaign.approve!(admin, campaign.review_digest)
        campaign.update!(status: 'running')
        allow(inbox.channel).to receive(:send_template).and_return('provider-default')
      end

      it 'rechecks blacklist immediately before send' do
        account.jrc_campaign_blacklists.create!(phone_number: contact.phone_number)
        service.perform
        expect(recipient.reload).to be_skipped
        expect(recipient.deliveries.where.not(external_id: nil)).to be_empty
      end

      it 'rechecks a newly blocked contact before follow-up' do
        contact.update!(blocked: true)
        service.perform
        expect(recipient.reload).to be_skipped
      end

      it 'does not send after opt-in was revoked' do
        JrcCampaigns::Consent.find_by!(account: account, phone_number: contact.phone_number).update!(revoked_at: Time.current)
        service.perform
        expect(recipient.reload).to be_skipped
      end

      it 'does not send when canceled while waiting for the delivery claim' do
        allow(service).to receive(:claim_delivery).and_wrap_original do |original|
          delivery = original.call
          campaign.cancel!
          delivery
        end
        service.perform
        expect(inbox.channel).not_to have_received(:send_template)
        expect(campaign.reload).to be_canceled
      end

      it 'preserves paused work when paused while waiting for the delivery claim' do
        allow(service).to receive(:claim_delivery).and_wrap_original do |original|
          delivery = original.call
          campaign.pause!
          delivery
        end
        service.perform
        expect(inbox.channel).not_to have_received(:send_template)
        expect(recipient.reload.metadata['pending_step_id']).to eq(step.id)

        allow(service).to receive(:claim_delivery).and_call_original
        campaign.resume!
        service.perform
        expect(inbox.channel).to have_received(:send_template).once
      end

      it 'never repeats a provider send when a duplicate job encounters a durable claim' do
        recipient.deliveries.create!(step: step, inbox: inbox, status: 'sending')
        expect(inbox.channel).not_to receive(:send_template)
        service.perform
        expect(recipient.deliveries.sole.reload.status).to eq('sending')
      end

      it 'preserves sent state when local synchronization fails and reconciles without resending' do
        allow(inbox.channel).to receive(:send_template).and_return('provider-accepted-1')
        allow(service).to receive(:attach_existing_conversation).and_raise('Local sync failed')
        service.perform
        delivery = recipient.deliveries.sole
        expect(delivery.status).to eq('sent')
        expect(delivery.external_id).to eq('provider-accepted-1')
        allow(service).to receive(:attach_existing_conversation).and_call_original
        service.perform
        expect(inbox.channel).to have_received(:send_template).once
        expect(delivery.reload.metadata['reconciled_at']).to be_present
      end

      it 'claims delivery before the provider boundary so an overlapping job cannot send again' do
        calls = 0
        allow(inbox.channel).to receive(:send_template) do
          calls += 1
          raise 'Duplicate external request' if calls > 1

          overlapping_job = JrcCampaigns::DispatchStepService.new(recipient: recipient, step: step)
          overlapping_job.perform
          'provider-accepted-overlap'
        end
        service.perform
        expect(inbox.channel).to have_received(:send_template).once
        expect(recipient.deliveries.sole.external_id).to eq('provider-accepted-overlap')
      end

      it 'never retries an ambiguous provider timeout' do
        allow(inbox.channel).to receive(:send_template).and_raise(Timeout::Error)
        service.perform
        service.perform
        expect(inbox.channel).to have_received(:send_template).once
        expect(recipient.deliveries.sole.status).to eq('unknown')
      end

      it 'keeps execution open while an approved follow-up is pending' do
        campaign.update!(status: 'draft')
        campaign.steps.create!(kind: 'template', position: 1, template_name: 'sample_shipping_confirmation', template_language: 'en_US')
        campaign.request_review!
        campaign.approve!(admin, campaign.review_digest)
        campaign.update!(status: 'running')
        allow(inbox.channel).to receive(:send_template).and_return('first-step')
        service.perform
        JrcCampaigns::ExecutionCompletionService.new(execution).check!
        expect(execution.reload).to be_running
      end

      it 'preserves a provider-confirmed failure during local reconciliation' do
        recipient.deliveries.create!(step: step, inbox: inbox, status: 'failed', external_id: 'accepted-then-rejected',
                                     sent_at: Time.current, failed_at: Time.current)
        recipient.update!(status: 'failed', error_message: 'Provider rejected delivery')
        service.perform
        expect(recipient.reload).to be_failed
        expect(recipient.error_message).to eq('Provider rejected delivery')
      end

      it 'does not complete a canceled campaign while reconciling accepted delivery' do
        recipient.deliveries.create!(step: step, inbox: inbox, status: 'sent', external_id: 'accepted-before-cancel', sent_at: Time.current)
        campaign.cancel!
        service.perform
        expect(campaign.reload).to be_canceled
        expect(execution.reload).to be_canceled
      end
    end
  end

  it 'blocks test messages without opt-in' do
    service = JrcCampaigns::TestMessageService.new(account: account, user: admin, phone_number: contact.phone_number,
                                                   inbox_id: inbox.id, step: { kind: 'text', body: 'Hello' })
    expect { service.perform }.to raise_error(ArgumentError, /consent/i)
  end
end
