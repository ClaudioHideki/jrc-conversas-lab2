# frozen_string_literal: true

# Filter the complete source-specific command; native Task content stays in Projects.
Rails.application.config.filter_parameters += %i[recording_task idempotency_key request_fingerprint]
