ANTHROPIC_API_KEY = Rails.application.credentials.anthropic_api_key ||
                    ENV["ANTHROPIC_API_KEY"]

raise "ANTHROPIC_API_KEY is not set (add it to credentials or ENV)" if ANTHROPIC_API_KEY.blank?
