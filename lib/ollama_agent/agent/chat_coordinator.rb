# frozen_string_literal: true

module OllamaAgent
  class Agent
    # Builds chat requests and resolves assistant messages (blocking vs streaming).
    class ChatCoordinator
      def initialize(client:, model_manager:, config:, hooks:)
        @client = client
        @model_manager = model_manager
        @config = config
        @hooks = hooks
        @current_turn = 0
      end

      def assistant_message(messages)
        if @hooks.subscribed?(:on_token)
          stream_assistant_message(messages)
        else
          block_assistant_message(messages)
        end
      end

      def request_args(messages)
        base_chat_request_args(messages).tap do |args|
          th = ThinkParam.effective_for_model(ThinkParam.resolve(@config.runtime.think), @model_manager.model)
          args[:think] = th unless th.nil?
        end
      end

      private

      def base_chat_request_args(messages)
        {
          messages: messages,
          tools: OllamaAgent.tools_for(read_only: @config.runtime.read_only, orchestrator: @config.runtime.orchestrator),
          model: @model_manager.model,
          options: { temperature: 0.2 }
        }
      end

      def block_assistant_message(messages)
        response = @client.chat(**request_args(messages))
        message = response.message
        raise EmptyAssistantMessageError, "Empty assistant message" if message.nil?

        GemmaThoughtContentParser.merge_into_message_data!(message)
        announce_assistant_content(message)
        message
      end

      def stream_assistant_message(messages)
        response = @client.chat(**request_args(messages), hooks: ollama_stream_hooks)
        message = response.message
        raise EmptyAssistantMessageError, "Empty assistant message" if message.nil?

        GemmaThoughtContentParser.merge_into_message_data!(message)
        message
      end

      def ollama_stream_hooks
        turn = -> { @current_turn }
        {
          on_thinking: stream_on_thinking_hook(turn),
          on_token: stream_on_token_hook(turn)
        }
      end

      def stream_on_thinking_hook(turn_proc)
        lambda do |fragment|
          @hooks.emit(:on_thinking, { token: fragment.to_s, turn: turn_proc.call })
        end
      end

      def stream_on_token_hook(turn_proc)
        lambda do |*args|
          token = args[0]
          logprobs = args[1]
          payload = { token: token, turn: turn_proc.call }
          payload[:logprobs] = logprobs unless logprobs.nil?
          @hooks.emit(:on_token, payload)
        end
      end

      def announce_assistant_content(message)
        @hooks.emit(:on_assistant_message, { message: message })
        return if @hooks.subscribed?(:on_assistant_message)

        Console.puts_assistant_message(message)
      end
    end
  end
end