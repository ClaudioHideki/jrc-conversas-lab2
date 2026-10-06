require 'minitest/autorun'
require 'date'
module JrcCrm; end
require_relative '../../app/services/jrc_crm/proposal_public_state'

class ProposalPublicStateTest < Minitest::Test
  Proposal = Struct.new(:status, :approval_status, :sent_at, :public_token_expires_at, :valid_until,
                        :public_token_revoked_at, keyword_init: true)

  def setup
    @now = Time.utc(2026, 10, 5, 12)
    @proposal = Proposal.new(status: 'draft', approval_status: 'not_required')
  end

  def test_pre_send_states_never_expose_content_or_allow_customer_transitions
    %w[draft pending_approval approved].each do |status|
      @proposal.status = status
      refute JrcCrm::ProposalPublicState.call(@proposal, now: @now)[:available]
      %w[viewed accepted rejected].each do |target|
        refute JrcCrm::ProposalPublicState.transition_allowed?(from: status, to: target, sent_at: @now)
      end
    end
  end

  def test_internal_approval_is_ready_for_delivery_without_becoming_sent
    @proposal.approval_status = 'approved'
    state = JrcCrm::ProposalPublicState.call(@proposal, now: @now)
    assert_equal 'approved', state[:state]
    refute state[:available]
    assert_includes state[:message], 'aguardando envio'
  end

  def test_sent_and_viewed_require_a_real_send_timestamp
    %w[sent viewed].each do |status|
      @proposal.status = status
      refute JrcCrm::ProposalPublicState.call(@proposal, now: @now)[:available]
      @proposal.sent_at = @now
      assert JrcCrm::ProposalPublicState.call(@proposal, now: @now)[:available]
      assert JrcCrm::ProposalPublicState.transition_allowed?(from: status, to: 'viewed', sent_at: @now)
      assert JrcCrm::ProposalPublicState.transition_allowed?(from: status, to: 'accepted', sent_at: @now)
      @proposal.sent_at = nil
    end
  end

  def test_terminal_states_do_not_allow_another_customer_transition
    %w[accepted rejected canceled].each do |status|
      refute JrcCrm::ProposalPublicState.transition_allowed?(from: status, to: 'viewed', sent_at: @now)
      refute JrcCrm::ProposalPublicState.transition_allowed?(from: status, to: 'accepted', sent_at: @now)
    end
  end

  def test_expiration_and_revocation_hide_contents_even_after_sending
    @proposal.status = 'sent'
    @proposal.sent_at = @now
    @proposal.valid_until = @now.to_date - 1
    state = JrcCrm::ProposalPublicState.call(@proposal, now: @now)
    assert_equal 'expired', state[:state]
    refute state[:available]
    @proposal.valid_until = nil
    @proposal.public_token_expires_at = @now
    assert_equal 'expired', JrcCrm::ProposalPublicState.call(@proposal, now: @now)[:state]
    @proposal.public_token_revoked_at = @now
    assert_equal 'canceled', JrcCrm::ProposalPublicState.call(@proposal, now: @now)[:state]
  end
end
