# frozen_string_literal: true

module OllamaAgent
  module Session
    # Lightweight value object for session metadata.
    SessionMeta = Struct.new(:session_id, :path, :started_at)
  end
end
