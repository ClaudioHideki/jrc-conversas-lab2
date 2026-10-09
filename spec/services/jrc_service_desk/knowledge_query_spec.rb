# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcServiceDesk::KnowledgeQuery do
  include_context 'JRC Service Desk domain'

  let(:query) { described_class.new(user_context: sd_context) }
  let(:portal) { create(:portal, account: sd_account) }

  before { sd_account.enable_features!('help_center') }

  it 'reuses only published articles in the native account and active portal' do
    published = create(:article, portal: portal, account: sd_account, title: 'Public restoration guide')
    create(:article, portal: portal, account: sd_account, status: :draft, title: 'Internal draft')
    create(:article, portal: portal, account: sd_account, status: :archived, title: 'Archived')
    create(:article)
    items = query.call[:items]
    expect(items.pluck(:id)).to eq([published.id.to_s])
    expect(items.first).to include(source: 'native_help_center', visibility: 'published_public')
    expect(items.first[:path]).to start_with('/hc/')
    expect(items.first).not_to have_key(:draft_content)
  end

  it 'does not expose draft locales or archived portals' do
    portal.update!(config: { allowed_locales: %w[en pt_BR], default_locale: 'en', draft_locales: ['pt_BR'] })
    create(:article, portal: portal, account: sd_account, locale: 'pt_BR')
    create(:article, portal: create(:portal, account: sd_account, archived: true), account: sd_account)
    expect(query.call[:items]).to be_empty
  end

  it 'escapes SQL wildcard characters rather than broadening a title search' do
    create(:article, portal: portal, account: sd_account, title: 'General guide')
    literal = create(:article, portal: portal, account: sd_account, title: '100% restored')
    expect(query.call(parameters: { query: '%' })[:items].pluck(:id)).to eq([literal.id.to_s])
  end

  it 'rejects a foreign portal identifier instead of returning that portal articles' do
    foreign = create(:portal)
    expect { query.call(parameters: { portal_id: foreign.id }) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'rechecks membership revocation instead of trusting a cached operator context' do
    sd_membership.update!(active: false)
    expect { query.call }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'requires the native help-center feature as well as service desk grants' do
    sd_account.disable_features!('help_center')
    expect { query.call }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'rejects unsupported filters and malformed search input' do
    [{ query: ['secret'] }, { status: 'draft' }, { page: 10_001 }].each do |parameters|
      expect { query.call(parameters: parameters) }.to raise_error(ArgumentError)
    end
  end
end
