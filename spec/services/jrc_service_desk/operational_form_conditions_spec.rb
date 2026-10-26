# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Operational conditions using native catalogue forms' do
  include_context 'JRC Service Desk domain'
  before { sd_as_admin! }
  let(:service) do
    JrcServiceDesk::CreateServiceDefinitionService.new(user_context: sd_context).call(unit_id: sd_unit.id,
      attributes: { name: 'Synthetic scoped form service', code: 'synthetic-form', active: true, form_fields: [
        { 'key' => 'complexity', 'label' => 'Complexidade sintética', 'type' => 'select', 'required' => false, 'options' => %w[simple advanced] }
      ] })
  end
  let(:queue) { create(:jrc_sd_queue, unit: sd_unit) }
  let(:rule) do
    { 'key' => 'explicit-complexity', 'precedence' => 5, 'match' => { 'service_id' => service.id }, 'output' => { 'queue_id' => queue.id },
      'conditions' => { 'operator' => 'all', 'groups' => [{ 'operator' => 'all', 'items' => [
        { 'field' => 'form_value', 'operator' => 'eq', 'value' => { 'key' => 'complexity', 'value' => 'advanced' } }
      ] }] } }
  end
  let(:publisher) { JrcServiceDesk::PublishOperationalRulesService.new(user_context: sd_context) }

  it 'routes only exact catalogue values submitted to the selected source service' do
    publisher.call(unit_id: sd_unit.id, kind: 'routing', definition: { 'rules' => [rule] }, enabled: true, expected_version: 0)
    creation = JrcServiceDesk::CreateTicketService.new(user_context: sd_context)
    selected = creation.call(unit_id: sd_unit.id, service_id: service.id,
      attributes: sd_create_attributes.merge(service_fields: { 'complexity' => 'advanced' }), idempotency_key: 'explicit-complexity-match')
    other = creation.call(unit_id: sd_unit.id, service_id: service.id,
      attributes: sd_create_attributes.merge(service_fields: { 'complexity' => 'simple' }), idempotency_key: 'explicit-complexity-nonmatch')
    expect(selected.queue_id).to eq(queue.id)
    expect(other.queue_id).to be_nil
    expect(selected.service_fields).to eq('complexity' => 'advanced')
  end

  it 'rejects unknown, wrong-type and cross-unit catalogue references before publishing' do
    input = { unit_id: sd_unit.id, kind: 'routing', definition: { 'rules' => [rule] }, enabled: true, expected_version: 0 }
    predicate = rule['conditions']['groups'].first['items'].first
    predicate['value']['value'] = 'not-a-catalogue-option'
    expect { publisher.call(**input) }.to raise_error(ArgumentError)
    predicate['value']['value'] = 12
    expect { publisher.call(**input) }.to raise_error(ArgumentError)
    predicate['value'] = { 'key' => 'unknown', 'value' => 'advanced' }
    expect { publisher.call(**input) }.to raise_error(ArgumentError)
    rule['match'].delete('service_id')
    expect { publisher.call(**input) }.to raise_error(KeyError)
    foreign_service = JrcServiceDesk::CreateServiceDefinitionService.new(user_context: sd_context).call(unit_id: sd_other_unit.id,
      attributes: { name: 'Synthetic other-unit service', code: 'other-form', active: true })
    rule['match']['service_id'] = foreign_service.id
    expect { publisher.call(**input) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(JrcServiceDesk::OperationalRuleVersion.where(account: sd_account).count).to eq(0)
  end

  it 'does not satisfy a negative predicate when the actual field is absent' do
    rule['conditions']['groups'].first['items'].first['operator'] = 'neq'
    expect(JrcServiceDesk::OperationalRuleMatcher.call([rule], { 'service_id' => service.id, 'form_value' => {} })).to be_nil
  end

  it 'distinguishes disjoint values of one field from compatible conditions on two different fields' do
    left = rule
    right = Marshal.load(Marshal.dump(left))
    right['key'] = 'another'
    value = right['conditions']['groups'].first['items'].first['value']
    value['value'] = 'simple'
    expect(JrcServiceDesk::OperationalRuleConditions.conflicts([left, right])).to be_empty
    value['key'] = 'different-field'
    expect(JrcServiceDesk::OperationalRuleConditions.conflicts([left, right])).to eq([['explicit-complexity', 'another']])
  end
end
