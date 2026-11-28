# frozen_string_literal: true

# Keep the optional customer notice out of native request parameter logs.
Rails.application.config.filter_parameters += %i[recording_policy_draft]
