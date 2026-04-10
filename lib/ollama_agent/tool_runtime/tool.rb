# frozen_string_literal: true

module OllamaAgent
  module ToolRuntime
    # Plugin contract for tools used with {Registry}, {Executor}, and {Loop}.
    class Tool
      def name
        raise NotImplementedError, "#{self.class} must implement #name"
      end

      def description
        raise NotImplementedError, "#{self.class} must implement #description"
      end

      def schema
        raise NotImplementedError, "#{self.class} must implement #schema"
      end

      def call(args)
        raise NotImplementedError, "#{self.class} must implement #call"
      end
    end
  end
end
