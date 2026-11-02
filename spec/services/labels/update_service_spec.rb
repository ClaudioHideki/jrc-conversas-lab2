require 'rails_helper'

describe Labels::UpdateService do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:label) { create(:label, account: account) }
  let(:contact) { conversation.contact }

  before do
    conversation.label_list.add(label.title)
    conversation.save!

    contact.label_list.add(label.title)
    contact.save!
  end

  describe '#perform' do
    it 'renames native Service Desk tags only within the owning Account' do
      ticket = create(:jrc_sd_ticket, account: account, unit: create(:jrc_sd_unit, operator_company: create(:jrc_sd_operator_company, account: account)))
      foreign = create(:jrc_sd_ticket)
      ticket.update_labels([label.title])
      foreign.update_labels([label.title])
      described_class.new(new_label_title: 'renamed-synthetic', old_label_title: label.title, account_id: account.id).perform
      expect(ticket.reload.label_list).to eq(['renamed-synthetic'])
      expect(foreign.reload.label_list).to eq([label.title])
      expect(conversation.reload.label_list).to eq(['renamed-synthetic'])
      expect(contact.reload.label_list).to eq(['renamed-synthetic'])
    end

    it 'updates associated conversations/contacts labels' do
      expect(conversation.label_list).to eq([label.title])
      expect(contact.label_list).to eq([label.title])

      described_class.new(
        new_label_title: 'updated-label-title',
        old_label_title: label.title,
        account_id: account.id
      ).perform

      expect(conversation.reload.label_list).to eq(['updated-label-title'])
      expect(contact.reload.label_list).to eq(['updated-label-title'])
    end
  end
end
