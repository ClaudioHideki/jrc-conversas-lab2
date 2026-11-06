# Consumes the already authorized action cohort and recorded native calendar evidence.
class JrcRelationship::FirstActionDuration
  DECIMAL = /\A[+-]?(?:\d(?:_?\d)*(?:\.(?:\d(?:_?\d)*)?)?|\.\d(?:_?\d)*)(?:[eE][+-]?\d(?:_?\d)*)?\z/
  BASED_INTEGER = /\A[+-]?0(?:x[0-9a-f](?:_?[0-9a-f])*|o[0-7](?:_?[0-7])*|b[01](?:_?[01])*)\z/i

  def self.average_minutes(scope)
    count = 0
    mean = 0.0
    scope.where("metadata ? 'first_action_elapsed_seconds'").in_batches do |batch|
      batch.pluck(Arel.sql("metadata ->> 'first_action_elapsed_seconds'")).each do |raw|
        value = minutes(raw)
        next if value.nil?

        count += 1
        mean += (value - mean) / count
      end
    end
    count.positive? ? mean : nil
  end

  def self.minutes(raw)
    return unless raw.is_a?(String)

    seconds = seconds(raw.strip)
    seconds / 60 if seconds&.finite? && seconds >= 0
  end

  def self.seconds(text)
    return Float(text, exception: false) if DECIMAL.match?(text)
    return Integer(text, 0, exception: false)&.to_f if BASED_INTEGER.match?(text)

    nil
  end
  private_class_method :minutes, :seconds
end
