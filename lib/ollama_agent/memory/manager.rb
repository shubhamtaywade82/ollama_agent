# frozen_string_literal: true

require_relative "short_term"
require_relative "session_memory"
require_relative "long_term"

module OllamaAgent
  module Memory
    # Unified memory interface exposing all three tiers.
    #
    # Tier semantics:
    #   :short_term  — sliding window of the current run; cleared at run end
    #   :session     — key-value store for this session; persisted to YAML in project dir
    #   :long_term   — global persistent store in ~/.config/ollama_agent/memory/
    #
    # @example
    #   mem = OllamaAgent::Memory::Manager.new(root: Dir.pwd, session_id: "my-session")
    #   mem.record_tool_call("read_file", { path: "lib/agent.rb" }, "content...")
    #   mem.remember("project_lang", "Ruby", tier: :long_term)
    #   mem.recall("project_lang")   # => "Ruby"
    class Manager
      attr_reader :short_term, :session, :long_term

      def initialize(root:, session_id: nil, long_term_path: nil)
        @short_term = ShortTerm.new
        @session    = SessionMemory.new(root: root, session_id: session_id)
        @long_term  = LongTerm.new(base_path: long_term_path || LongTerm::DEFAULT_BASE)
      end

      # ── Short-term recording ─────────────────────────────────────────────

      def record_tool_call(tool_name, args, result = nil)
        @short_term.record(:tool_call,   { tool: tool_name.to_s, args: args })
        @short_term.record(:tool_result, { tool: tool_name.to_s, result: result.to_s[0, 500] }) if result
      end

      def record_observation(text)
        @short_term.record(:observation, text)
      end

      def recent_context(n = 10)
        @short_term.recent(n)
      end

      # ── Durable memory ────────────────────────────────────────────────────

      # Store a fact at the specified tier.
      # @param key       [String]
      # @param value     [Object]
      # @param tier      [Symbol]  :long_term or :session
      # @param namespace [String]  only used by long_term
      def remember(key, value, tier: :long_term, namespace: "default")
        case tier.to_sym
        when :long_term then @long_term.store(key.to_s, value, namespace: namespace)
        when :session   then @session.set(key.to_s, value)
        else raise ArgumentError, "Unknown memory tier: #{tier}"
        end
      end

      # Retrieve a fact from the specified tier.
      def recall(key, tier: :long_term, namespace: "default")
        case tier.to_sym
        when :long_term then @long_term.fetch(key.to_s, namespace: namespace)
        when :session   then @session.get(key.to_s)
        end
      end

      # Forget a fact from the specified tier.
      def forget(key, tier: :long_term, namespace: "default")
        case tier.to_sym
        when :long_term then @long_term.delete(key.to_s, namespace: namespace)
        when :session   then @session.delete(key.to_s)
        end
      end

      # List all keys in a tier/namespace.
      def list(tier: :long_term, namespace: "default")
        case tier.to_sym
        when :long_term then @long_term.all(namespace: namespace)
        when :session   then @session.all
        else {}
        end
      end

      # Search long-term memory for entries matching a pattern.
      def search(pattern, namespace: "default")
        @long_term.search(pattern, namespace: namespace)
      end

      # ── Goal tracking ─────────────────────────────────────────────────────

      def set_goal(description)
        @session.set_goal(description)
      end

      def complete_goal(description)
        @session.complete_goal(description)
      end

      def active_goals
        @session.active_goals
      end

      # ── Lifecycle ─────────────────────────────────────────────────────────

      # Call at the end of each run to clear short-term memory.
      def flush_short_term!
        @short_term.clear!
      end

      def summary
        {
          short_term_entries: @short_term.size,
          session_keys: @session.keys.size,
          long_term_namespaces: @long_term.namespaces.size
        }
      end
    end
  end
end
