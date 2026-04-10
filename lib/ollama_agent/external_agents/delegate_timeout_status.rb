# frozen_string_literal: true

module OllamaAgent
  module ExternalAgents
    # Stand-in Process::Status when Open3 does not return (Timeout).
    class DelegateTimeoutStatus
      def exitstatus
        124
      end
    end
  end
end
