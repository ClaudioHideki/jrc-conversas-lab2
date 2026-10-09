# frozen_string_literal: true

module JrcServiceDesk::SkillCodes
  def self.valid?(values)
    values.is_a?(Array) && values.uniq == values && values.size <= 50 && values.all? do |skill|
      skill.is_a?(String) && skill.match?(/\A[a-zA-Z0-9_.-]{1,80}\z/)
    end
  end
end
