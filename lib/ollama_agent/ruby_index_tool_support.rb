# frozen_string_literal: true

require_relative "ruby_index"
require_relative "ruby_search_modes"

module OllamaAgent
  # Prism Ruby index lookup for search_code (included by SandboxedTools).
  module RubyIndexToolSupport
    private

    def ruby_search_mode?(mode)
      RubySearchModes::ALL.include?(mode)
    end

    def search_code_ruby(pattern, mode)
      idx = ruby_index
      rows = ruby_index_rows(idx, mode, pattern)
      format_ruby_index_rows(rows, mode)
    end

    def ruby_index_rows(idx, mode, pattern)
      case mode
      when "class" then idx.search_class(pattern)
      when "module" then idx.search_module(pattern)
      when "constant" then idx.search_class_or_module(pattern)
      when "method" then idx.search_method(pattern)
      else
        []
      end
    end

    def format_ruby_index_rows(rows, mode)
      if RubySearchModes::CONSTANT_OUTPUT.include?(mode)
        RubyIndex::Formatter.format_constants(rows)
      else
        RubyIndex::Formatter.format_methods(rows)
      end
    end

    # Rebuild only when OLLAMA_AGENT_INDEX_REBUILD changes (avoids rebuilding on every call while it stays "1").
    def ruby_index
      @ruby_index_mutex ||= Mutex.new
      @ruby_index_mutex.synchronize { synchronized_ruby_index }
    end

    def synchronized_ruby_index
      invalidate_ruby_index_if_fingerprint_changed
      return @ruby_index if @ruby_index

      @ruby_index = RubyIndex.build(root: @root).tap do |idx|
        warn "ollama_agent: #{idx.summary_line}" if ENV["OLLAMA_AGENT_DEBUG"] == "1"
      end
    end

    def invalidate_ruby_index_if_fingerprint_changed
      fp = ENV.fetch("OLLAMA_AGENT_INDEX_REBUILD", "")
      return if fp == @ruby_index_cache_fingerprint

      @ruby_index = nil
      @ruby_index_cache_fingerprint = fp
    end
  end
end
