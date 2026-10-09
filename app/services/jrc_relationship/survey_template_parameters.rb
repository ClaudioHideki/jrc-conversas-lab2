# Shape validation for the existing native parser payload; no second renderer or converter.
class JrcRelationship::SurveyTemplateParameters
  def self.valid?(parts)
    return false unless parts.is_a?(Hash) && (parts.keys - %w[body header footer buttons]).empty?
    return false unless valid_text_parts?(parts)

    valid_buttons?(parts['buttons'])
  end

  def self.valid_text_parts?(parts)
    %w[body header footer].all? { |key| parts[key].nil? || text_map?(parts[key]) }
  end

  def self.valid_buttons?(buttons)
    return true if buttons.nil?

    buttons.is_a?(Array) && buttons.size <= 10 && buttons.all? { |button| valid_button?(button) }
  end

  def self.text_map?(value)
    value.is_a?(Hash) && value.size <= 20 && value.all? do |key, text|
      key.is_a?(String) && key.length <= 100 && text.is_a?(String) && text.length <= 4000
    end
  end

  def self.valid_button?(button)
    button.is_a?(Hash) && (button.keys - %w[type parameter]).empty? &&
      %w[url quick_reply copy_code].include?(button['type']) && button['parameter'].is_a?(String) && button['parameter'].length <= 4000
  end
  private_class_method :valid_text_parts?, :valid_buttons?, :text_map?, :valid_button?
end
