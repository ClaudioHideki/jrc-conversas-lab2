# frozen_string_literal: true

class JrcContactCenter::FactsProjector
  def initialize(account:)
    @account = account
  end

  def call(session_id)
    @account.with_lock do
      session = JrcContactCenter::CallSession.where(account: @account).find(session_id)
      session.with_lock { project(session) }
    end
  end

  private

  def project(session)
    return unless %w[ended failed].include?(session.status) && session.ended_at

    projection = JrcContactCenter::CallFactContribution.new(session: session).call
    previous = session.f1_data['projection']
    return if previous == projection

    apply(previous, -1) if previous
    apply(projection, 1)
    session.update_f1_data('projection' => projection)
  end

  def apply(projection, sign)
    dimensions = projection.fetch('dimensions').symbolize_keys
    fact = JrcContactCenter::DailyFact.find_or_initialize_by(dimensions.merge(account: @account))
    projection.fetch('values').each { |key, value| fact[key] = fact[key].to_i + (sign * value) }
    data = fact.data.merge('projection_contract' => 'call_session_v1')
    projection.fetch('measurements').each { |key, value| data[key] = data.fetch(key, 0) + (sign * value) }
    fact.update!(data: data)
  end
end
