require 'rails_helper'

RSpec.describe 'Native CRM deal product roundtrip', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :agent) }
  let(:headers) { actor.create_new_auth_token }
  let(:pipeline) { JrcCrm::DefaultPipelineService.new(account).perform }
  let(:deal) do
    account.jrc_crm_deals.create!(owner: actor, pipeline: pipeline, stage: pipeline.stages.active.order(:position).first,
                                  title: 'Synthetic native item scope', value_cents: 0)
  end
  let(:product) { account.jrc_crm_products.create!(name: 'Synthetic native item', sku: 'NATIVE-ROUNDTRIP', active: true, unit_price_cents: 10_000) }
  let(:item) { deal.deal_products.create!(product: product, quantity: 2, unit_price_cents: 10_000, discount_cents: 1000) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/deals/#{deal.id}/products" }

  before { account.enable_features!('jrc_crm') }

  it 'persists native add, update and detail totals using the unchanged client payload' do
    post base, headers: headers, params: { item: { product_id: product.id, quantity: 2, unit_price_cents: 10_000, discount_cents: 1000 } }, as: :json
    expect(response).to have_http_status(:created)
    id = response.parsed_body.first.fetch('id')
    expect(deal.reload.value_cents).to eq(19_000)
    patch "#{base}/#{id}", headers: headers, params: { item: { quantity: 3, unit_price_cents: 10_000, discount_cents: 1000 } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(deal.reload.value_cents).to eq(29_000)
    get "/api/v1/accounts/#{account.id}/crm/deals/#{deal.id}", headers: headers
    expect(response.parsed_body).to include('value_cents' => 29_000, 'products_count' => 1)
    expect(response.parsed_body.fetch('deal_products').first.fetch('quantity').to_d).to eq(3)
  end

  it 'removes an owned native item and recalculates the persisted total' do
    post base, headers: headers, params: { item: { product_id: product.id, quantity: 2, unit_price_cents: 10_000, discount_cents: 1000 } }, as: :json
    expect(response).to have_http_status(:created)
    id = response.parsed_body.first.fetch('id')
    expect(deal.reload.value_cents).to eq(19_000)
    delete "#{base}/#{id}", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(deal.reload.value_cents).to eq(0)
    expect(deal.deal_products).to be_empty
  end

  it 'denies another owner before changing the item or the deal' do
    other = create(:user, account: account, role: :agent)
    original = item.attributes.deep_dup
    patch "#{base}/#{item.id}", headers: other.create_new_auth_token, params: { item: { quantity: 3 } }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(item.reload.attributes).to eq(original)
  end

  it 'denies a foreign account item write without changing the original item' do
    foreign = create(:account)
    foreign.enable_features!('jrc_crm')
    outsider = create(:user, account: foreign, role: :administrator)
    original = item.attributes.deep_dup
    patch "/api/v1/accounts/#{foreign.id}/crm/deals/#{deal.id}/products/#{item.id}", headers: outsider.create_new_auth_token,
                                                                                     params: { item: { quantity: 3 } }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(item.reload.attributes).to eq(original)
  end

  it 'keeps the item lookup within its native deal instead of trusting a different deal item ID' do
    second = account.jrc_crm_deals.create!(owner: actor, pipeline: pipeline, stage: pipeline.stages.first, title: 'Other own native deal')
    other_item = second.deal_products.create!(product: product, quantity: 1, unit_price_cents: 10_000, discount_cents: 0)
    original = other_item.attributes.deep_dup
    patch "#{base}/#{other_item.id}", headers: headers, params: { item: { quantity: 3 } }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(other_item.reload.attributes).to eq(original)
  end

  it 'retains the persisted item when native quantity validation rejects an update' do
    original = item.attributes.deep_dup
    patch "#{base}/#{item.id}", headers: headers, params: { item: { quantity: 0 } }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(item.reload.attributes).to eq(original)
  end
end
