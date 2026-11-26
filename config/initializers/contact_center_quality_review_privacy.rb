# frozen_string_literal: true

# Reuse the native ending-history pattern: SQL bind logging reads Base filters, not the model's inspect filter.
private_quality_attributes = %i[quality_review original_analysis reviewed_values input_sha256 source_sha256 scope_snapshot]
Rails.application.config.filter_parameters += private_quality_attributes

ActiveSupport.on_load(:active_record) do
  self.filter_attributes += private_quality_attributes
end
