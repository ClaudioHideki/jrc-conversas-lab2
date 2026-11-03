require 'rails_helper'

RSpec.describe JrcCustomers::CampaignSegment do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:taxonomy) { JrcCustomers::Taxonomy.create!(account: account, name: 'Campaign customers', kind: 'segment', modules: ['campaigns']) }
  let(:company) { account.master_companies.create!(name: 'Selected customer', segment: taxonomy.name) }
  let(:contact) { create(:contact, account: account, company_id: company.id, email: 'selected@example.test') }
  let(:unmatched) { create(:contact, account: account, email: 'unmatched@example.test') }
  let(:campaign) do
    JrcCampaigns::Campaign.create!(account: account, created_by: actor, name: 'Segment draft', delivery_channel: 'email',
                                   audience_config: { customer_filters: { customer_segment_id: taxonomy.id } })
  end
  let(:segment) { described_class.new(campaign) }

  before do
    account.enable_features!('jrc_customer_master', 'jrc_campaigns')
    contact
    unmatched
  end

  it 'narrows canonical contacts and retains an explicitly included contact without a company' do
    JrcCustomers::SegmentOverride.create!(account: account, taxonomy: taxonomy, contact: unmatched, mode: 'include')
    original = [contact, unmatched].map { |row| row.reload.attributes }
    expect(JrcCampaigns::AudienceResolver.new(campaign).entries.map { |entry| entry.contact.id }).to contain_exactly(contact.id, unmatched.id)
    expect([contact, unmatched].map { |row| row.reload.attributes }).to eq(original)
    expect(JrcCampaigns::Consent.where(account: account)).to be_empty
  end

  it 'retains exclusions instead of falling back to the matching company' do
    JrcCustomers::SegmentOverride.create!(account: account, taxonomy: taxonomy, contact: contact, mode: 'exclude')
    expect(JrcCampaigns::AudienceResolver.new(campaign).entries).to eq([])
  end

  it 'uses fresh persisted creator authority without borrowing an ambient administrator' do
    campaign
    account.account_users.find_by!(user: actor).update!(role: :agent)
    expect { segment.apply(account.contacts) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'rejects creator identifiers inside audience configuration and fails closed without a trusted creator' do
    campaign
    campaign.created_by = nil
    campaign.audience_config['user_id'] = actor.id
    expect { segment.apply(account.contacts) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'requires the customer master module separately from native campaign administrator access' do
    campaign
    account.disable_features!('jrc_customer_master')
    expect { segment.apply(account.contacts) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'checks the current operator in addition to the persisted creator before preview or review' do
    campaign
    other = create(:user, account: account, role: :administrator)
    company.update!(relationship_type: 'internal')
    account.jrc_crm_business_units.create!(name: 'Selected unit', code: 'CAM-SEG-A', company_id: company.id)
    issuer = account.master_companies.create!(name: 'Other operator', relationship_type: 'internal')
    unit = account.jrc_crm_business_units.create!(name: 'Other unit', code: 'CAM-SEG-B', company_id: issuer.id)
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'GROUP', structure_managed: true)
    account.jrc_crm_user_business_units.create!(user: other, business_unit: unit, scope: 'BUSINESS_UNIT', structure_managed: true)
    expect { segment.authorize_viewer!(other) }.to raise_error(Pundit::NotAuthorizedError)
    expect { segment.authorize_viewer!(actor) }.not_to raise_error
  end

  it 'rejects a foreign segment even when the creator also administers the other account' do
    campaign
    foreign = create(:account)
    create(:account_user, account: foreign, user: actor, role: :administrator)
    other = JrcCustomers::Taxonomy.create!(account: foreign, name: 'Foreign campaigns', kind: 'segment', modules: ['campaigns'])
    campaign.audience_config['customer_filters']['customer_segment_id'] = other.id
    expect { segment.apply(account.contacts) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'rechecks publication, active state and the campaign module on each call' do
    campaign
    taxonomy.update!(modules: ['crm'])
    expect { segment.apply(account.contacts) }.to raise_error(ActiveRecord::RecordNotFound)
    taxonomy.update!(modules: ['campaigns'], active: false)
    expect { segment.apply(account.contacts) }.to raise_error(ActiveRecord::RecordNotFound)
    account.disable_features!('jrc_campaigns')
    expect { segment.apply(account.contacts) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'rejects sanitized lists instead of silently dropping the canonical customer restriction' do
    campaign.audience_type = 'sanitized_list'
    expect { JrcCampaigns::AudienceResolver.new(campaign).entries }.to raise_error(JrcCustomers::CampaignFilter::InvalidFilter)
  end

  it 'hashes membership without including names, destinations or full contact data' do
    evidence = segment.review_evidence
    expect(evidence.keys).to contain_exactly('definition_sha256', 'contact_ids_sha256')
    expect(evidence.values).to all(match(/\A[0-9a-f]{64}\z/))
    expect(evidence.to_json).not_to include(contact.email, contact.name, actor.email)
    JrcCustomers::SegmentOverride.create!(account: account, taxonomy: taxonomy, contact: unmatched, mode: 'include')
    expect(segment.review_evidence).not_to eq(evidence)
  end

  it 'invalidates a human approval after the segment definition or membership changes' do
    campaign.request_review!
    campaign.approve!(actor, campaign.review_digest)
    expect(JrcCampaigns::ApprovalService.new(campaign).locally_valid?).to be(true)
    JrcCustomers::SegmentOverride.create!(account: account, taxonomy: taxonomy, contact: unmatched, mode: 'include')
    expect(JrcCampaigns::ApprovalService.new(campaign.reload).locally_valid?).to be(false)
    expect(campaign.executions).to be_empty
    expect(JrcCampaigns::Recipient.where(campaign: campaign)).to be_empty
  end

  it 'reports invalid approval rather than raising a presentation error after creator permission revocation' do
    campaign.request_review!
    campaign.approve!(actor, campaign.review_digest)
    account.account_users.find_by!(user: actor).update!(role: :agent)
    expect(JrcCampaigns::ApprovalService.new(campaign.reload).locally_valid?).to be(false)
    expect { campaign.ensure_approved! }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'invalidates an approval when publication changes even if the matching contacts remain the same' do
    campaign.request_review!
    campaign.approve!(actor, campaign.review_digest)
    taxonomy.update!(modules: %w[campaigns crm])
    expect(segment.apply(account.contacts).pluck(:id)).to eq([contact.id])
    expect(JrcCampaigns::ApprovalService.new(campaign.reload).locally_valid?).to be(false)
    taxonomy.update!(modules: ['crm'])
    expect(JrcCampaigns::ApprovalService.new(campaign.reload).locally_valid?).to be(false)
  end

  it 'requires native CRM access for billed-order criteria instead of treating inaccessible finance as zero' do
    campaign
    rule = { field: 'invoiced_revenue', operator: 'at_least', value: '123.45', period_start: '2026-10-01', period_end: '2026-10-31' }
    taxonomy.update!(selection_mode: 'dynamic', criteria: { match: 'all', rules: [rule] })
    expect { segment.apply(account.contacts) }.to raise_error(Pundit::NotAuthorizedError)
    account.enable_features!('jrc_crm')
    account.jrc_crm_sales_orders.create!(owner: actor, contact: contact, source_type: 'manual', order_origin: 'direct_sale',
                                         status: 'invoiced', total_cents: 12_345, sold_at: '2026-10-15T12:00:00Z')
    expect(segment.apply(account.contacts).pluck(:id)).to eq([contact.id])
  end

  it 'preserves legacy campaigns with no selected customer segment and no recorded creator' do
    legacy = JrcCampaigns::Campaign.create!(account: account, name: 'Legacy draft', delivery_channel: 'email')
    expect(described_class.new(legacy).selected?).to be(false)
    expect(JrcCampaigns::AudienceResolver.new(legacy).entries.map { |entry| entry.contact.id }).to contain_exactly(contact.id, unmatched.id)
    expect(JrcCampaigns::ReviewConfiguration.new(legacy).local_configuration).not_to have_key('customer_segment')
  end

  it 'rejects an out-of-segment recipient introduced during a simulated review race without sending anything' do
    entries = JrcCampaigns::AudienceResolver.new(campaign).entries
    outside = JrcCampaigns::AudienceResolver::Entry.new(contact: unmatched, name: unmatched.name, phone_number: nil,
                                                        email: unmatched.email, source: 'all_contacts', metadata: {})
    resolver = instance_double(JrcCampaigns::AudienceResolver, entries: entries + [outside])
    allow(JrcCampaigns::AudienceResolver).to receive(:new).with(campaign).and_return(resolver)
    campaign.request_review!
    expect { campaign.approve!(actor, campaign.review_digest) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(campaign.executions).to be_empty
    expect(campaign.approved_at).to be_nil
  end
end
