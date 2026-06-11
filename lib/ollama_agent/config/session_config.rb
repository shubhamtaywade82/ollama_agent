# frozen_string_literal: true

module OllamaAgent
  module Config
    SessionConfig = Data.define(:session_id, :resume, :max_tokens, :context_summarize,
                                :stdin, :stdout, :user_prompt, :logger) do
      def initialize(session_id: nil, resume: false, max_tokens: nil, context_summarize: nil,
                     stdin: $stdin, stdout: $stdout, user_prompt: nil, logger: nil)
        super
      end
    end
  end
end