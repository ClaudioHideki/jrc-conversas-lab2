# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcServiceDesk::UiCapabilityProjection do
  include_context 'JRC Service Desk domain'

  let(:context) { JrcServiceDesk::OperationalContext.new(sd_context) }
  let(:grants) do
    JrcServiceDesk::Capabilities::DEFAULTS.fetch('agent').map { |key| "jrc_service_desk_#{key}" } +
      %w[contact_manage jrc_relationship_view]
  end
  let(:role) { create(:custom_role, account: sd_account, permissions: grants) }

  before { sd_account.enable_features!('jrc_customer_master', 'jrc_relationship') }

  it 'advertises shared surveys only when native Service Desk and Relationship access both authorize the operator' do
    projection = described_class.new(context).call
    expect(projection.fetch('surveys')).to eq(index: true)
    expect(projection.fetch('tickets')).to eq(index: true)
    expect(projection.fetch('tasks')).to eq(index: true)
    expect(projection.fetch('settings')).to eq(index: false)
    expect(projection.fetch('lifecycle_policies')).to eq(index: false, publish: false)
    expect(projection.fetch('automations')).to eq(index: false)
    expect(projection.fetch('notifications')).to eq(manage: false)
  end

  %w[jrc_relationship jrc_customer_master].each do |flag|
    it "removes shared surveys after the real #{flag} feature is revoked without widening existing capabilities" do
      initial = described_class.new(context).call
      expect(initial.fetch('surveys')).to eq(index: true)
      sd_account.disable_features!(flag)
      refreshed = described_class.new(JrcServiceDesk::OperationalContext.new(sd_context)).call
      expect(refreshed.fetch('surveys')).to eq(index: false)
      expect(refreshed.fetch('tickets')).to eq(initial.fetch('tickets'))
      expect(refreshed.fetch('settings')).to eq(initial.fetch('settings'))
      expect(refreshed.fetch('notifications')).to eq(initial.fetch('notifications'))
    end
  end

  it 'honors a current native custom role with the two independent module grants' do
    sd_account_user.update!(custom_role: role)
    refreshed = JrcServiceDesk::OperationalContext.new(sd_context)
    expect(JrcRelationship::ModulePolicy.new(refreshed.to_h, sd_account).access?).to be(true)
    projection = described_class.new(refreshed).call
    expect(projection.fetch('surveys')).to eq(index: true)
    expect(projection.fetch('tickets')).to eq(index: true)
    expect(projection.fetch('settings')).to eq(index: false)
  end

  it 'does not let a custom administrator role bypass a revoked Relationship permission' do
    sd_account_user.update!(role: :administrator, custom_role: role)
    initial = described_class.new(JrcServiceDesk::OperationalContext.new(sd_context)).call
    expect(initial.fetch('surveys')).to eq(index: true)
    role.update!(permissions: grants - ['jrc_relationship_view'])
    refreshed = described_class.new(JrcServiceDesk::OperationalContext.new(sd_context)).call
    expect(refreshed.fetch('surveys')).to eq(index: false)
    expect(refreshed.fetch('tickets')).to eq(initial.fetch('tickets'))
    expect(refreshed.fetch('settings')).to eq(index: false)
    expect(refreshed.fetch('automations')).to eq(index: false)
  end

  %w[tickets_view customers_view].each do |key|
    it "does not widen shared survey access when the independent Service Desk #{key} capability is revoked" do
      sd_account_user.update!(custom_role: role)
      expect(described_class.new(JrcServiceDesk::OperationalContext.new(sd_context)).call.fetch('surveys')).to eq(index: true)
      role.update!(permissions: grants - ["jrc_service_desk_#{key}"])
      refreshed = described_class.new(JrcServiceDesk::OperationalContext.new(sd_context)).call
      expect(refreshed.fetch('surveys')).to eq(index: false)
      expect(refreshed.fetch('settings')).to eq(index: false)
      expect(refreshed.fetch('lifecycle_policies')).to eq(index: false, publish: false)
    end
  end

  it 'closes the native UI context after the Service Desk feature is revoked' do
    initial = JrcServiceDesk::UiContextService.new(user_context: sd_context).call
    expect(initial.dig(:capabilities, 'surveys')).to eq(index: true)
    sd_account.disable_features!('jrc_service_desk')
    expect { JrcServiceDesk::UiContextService.new(user_context: sd_context).call }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'closes the native UI context after the current account is suspended' do
    expect(JrcServiceDesk::UiContextService.new(user_context: sd_context).call.dig(:capabilities, 'surveys')).to eq(index: true)
    sd_account.update!(status: :suspended)
    expect { JrcServiceDesk::UiContextService.new(user_context: sd_context).call }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'does not project foreign-account grants through an inconsistent native identity' do
    foreign = create(:account_user, account: sd_foreign_account, user: sd_user, role: :administrator)
    invalid = sd_context.merge(account_user: foreign)
    expect(JrcServiceDesk::OperationalContext.new(invalid).native_operator?).to be(false)
    expect { JrcServiceDesk::UiContextService.new(user_context: invalid).call }.to raise_error(Pundit::NotAuthorizedError)
  end
end
