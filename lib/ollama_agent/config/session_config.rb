# frozen_string_literal: true

module OllamaAgent
  module Config
    class SessionConfig
      attr_reader :session_id, :resume, :max_tokens, :context_summarize, :stdin, :stdout, :user_prompt, :logger

      def initialize(session_id: nil, resume: false, max_tokens: nil, context_summarize: nil,
                     stdin: $stdin, stdout: $stdout, user_prompt: nil, logger: nil)
        @session_id = session_id
        @resume = resume
        @max_tokens = max_tokens
        @context_summarize = context_summarize
        @stdin = stdin
        @stdout = stdout
        @user_prompt = user_prompt
        @logger = logger
      end
    end
  end
end