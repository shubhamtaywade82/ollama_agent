# frozen_string_literal: true

module OllamaAgent
  class Agent
    module ClientWiring
      private

      def build_default_client
        @client_manager.build_default_client
      end

      def resolved_audit_enabled
        @client_manager.resolved_audit_enabled
      end

      def audit_log_dir
        @client_manager.audit_log_dir
      end

      def attach_audit_logger
        @client_manager.attach_audit_logger
      end
    end
  end
end