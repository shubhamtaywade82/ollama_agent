# frozen_string_literal: true

require_relative "ruby_index/builder"
require_relative "ruby_index/formatter"
require_relative "ruby_index/index"
require_relative "ruby_index/naming"

module OllamaAgent
  # Prism-based index of Ruby class/module/method definitions under a project root.
  module RubyIndex
    module_function

    def build(root:, max_files: nil, max_file_bytes: nil)
      Builder.build(root: root, max_files: max_files, max_file_bytes: max_file_bytes)
    end
  end
end
