# frozen_string_literal: true

# Test data only. This file creates no application seed or default operational unit.
FactoryBot.define do
  factory :jrc_sd_operator_company, class: 'JrcServiceDesk::OperatorCompany' do
    account
    sequence(:code) { |n| "operator-#{n}" }
    name { 'Test operator' }
    active { true }
  end

  factory :jrc_sd_unit, class: 'JrcServiceDesk::Unit' do
    operator_company { association(:jrc_sd_operator_company) }
    account { operator_company.account }
    sequence(:code) { |n| "unit-#{n}" }
    name { 'Test unit' }
    active { true }
  end

  factory :jrc_sd_membership, class: 'JrcServiceDesk::UnitMembership' do
    unit { association(:jrc_sd_unit) }
    account { unit.account }
    account_user { association(:account_user, account: account) }
    active { true } # Explicit grant in a test, not the database default.
  end

  factory :jrc_sd_status, class: 'JrcServiceDesk::TicketStatus' do
    unit { association(:jrc_sd_unit) }
    account { unit.account }
    sequence(:code) { |n| "status-#{n}" }
    name { 'Test initial state' }
    active { true }
    phase { 'open' }
    initial { true }
    position { 0 }
  end

  factory :jrc_sd_priority, class: 'JrcServiceDesk::Priority' do
    unit { association(:jrc_sd_unit) }
    account { unit.account }
    sequence(:code) { |n| "priority-#{n}" }
    name { 'Test priority' }
    position { 1 }
    active { true }
  end

  factory :jrc_sd_category, class: 'JrcServiceDesk::Category' do
    unit { association(:jrc_sd_unit) }
    account { unit.account }
    sequence(:code) { |n| "category-#{n}" }
    name { 'Test category' }
    active { true }
  end

  factory :jrc_sd_queue, class: 'JrcServiceDesk::Queue' do
    unit { association(:jrc_sd_unit) }
    account { unit.account }
    sequence(:code) { |n| "queue-#{n}" }
    name { 'Test work queue' }
    active { true }
  end

  factory :jrc_sd_ticket, class: 'JrcServiceDesk::Ticket' do
    unit { association(:jrc_sd_unit) }
    account { unit.account }
    title { 'Test ticket' }
    description { 'Fixture for isolated database tests' }
    requester { association(:contact, account: account) }
    status { association(:jrc_sd_status, unit: unit) }
    priority { association(:jrc_sd_priority, unit: unit) }
    created_by_membership { association(:jrc_sd_membership, unit: unit) }
    origin_channel { 'manual' }
    opened_at { Time.current }
    idempotency_key { SecureRandom.uuid }
    request_fingerprint { 'a' * 64 }
  end

  factory :jrc_sd_note, class: 'JrcServiceDesk::TicketNote' do
    ticket { association(:jrc_sd_ticket) }
    account { ticket.account }
    unit { ticket.unit }
    author_membership { ticket.created_by_membership }
    body { 'Internal test note' }
    visibility { 'internal' }
    idempotency_key { SecureRandom.uuid }
    request_fingerprint { JrcServiceDesk::CanonicalJson.digest('body' => body) }
  end

  factory :jrc_sd_event, class: 'JrcServiceDesk::TicketEvent' do
    ticket { association(:jrc_sd_ticket) }
    account { ticket.account }
    unit { ticket.unit }
    actor_membership { ticket.created_by_membership }
    event_type { 'ticket_created' }
    data { {} }
  end

  factory :jrc_sd_snapshot, class: 'JrcServiceDesk::SlaSnapshot' do
    ticket { association(:jrc_sd_ticket) }
    account { ticket.account }
    unit { ticket.unit }
    version { 1 }
    source_system { 'test-contract-source' }
    source_reference { 'test-contract-1' }
    source_version { 'test-v1' }
    policy_key { 'test-policy' }
    policy_version { '1' }
    policy_conditions { { 'first_response_seconds' => 1800, 'resolution_seconds' => 7200 } }
    calendar_key { 'test-calendar' }
    calendar_version { '1' }
    calendar_scope { 'unit' }
    calendar_conditions { { 'weekdays' => [1, 2, 3, 4, 5], 'working_hours' => ['09:00-17:00'], 'holidays' => [], 'exceptions' => [] } }
    contract_conditions { { 'coverage' => 'test-service' } }
    timezone { 'America/Sao_Paulo' }
    captured_at { Time.utc(2026, 9, 25, 10) }
    applied_at { Time.current }
    after(:build) { |snapshot| snapshot.payload_digest = snapshot.expected_digest }
  end

  factory :jrc_sd_milestone, class: 'JrcServiceDesk::SlaMilestone' do
    sla_snapshot { association(:jrc_sd_snapshot) }
    ticket { sla_snapshot.ticket }
    account { ticket.account }
    unit { ticket.unit }
    kind { 'first_response' }
  end

  factory :jrc_sd_conversation_link, class: 'JrcServiceDesk::TicketConversation' do
    ticket { association(:jrc_sd_ticket) }
    account { ticket.account }
    unit { ticket.unit }
    conversation { association(:conversation, account: account) }
    linked_by_membership { ticket.created_by_membership }
  end
end
