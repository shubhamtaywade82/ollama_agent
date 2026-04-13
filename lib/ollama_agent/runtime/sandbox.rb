# frozen_string_literal: true

require "fileutils"
require "tmpdir"

module OllamaAgent
  module Runtime
    # Workspace sandbox: copies a project to a temp directory for isolated edits.
    # Used by self-improvement and automated modes to prevent live-tree mutations.
    #
    # @example
    #   sandbox = OllamaAgent::Runtime::Sandbox.new(source_root: "/my/project")
    #   sandbox.setup!
    #   # agent runs inside sandbox.root
    #   sandbox.changed_files  # => list of modified files
    #   sandbox.sync_back!(target: "/my/project")  # merge changes
    #   sandbox.teardown!
    class Sandbox
      attr_reader :root, :source_root

      IGNORED_DIRS = %w[.git node_modules vendor .bundle tmp log coverage .ollama_agent].freeze

      def initialize(source_root:, prefix: "ollama_agent_sandbox")
        @source_root = File.expand_path(source_root)
        @prefix      = prefix
        @root        = nil
        @setup_done  = false
      end

      # Copy source tree to a temp directory.
      # @return [String] sandbox root path
      def setup!
        @root = Dir.mktmpdir(@prefix)
        copy_tree(@source_root, @root)
        @setup_done = true
        @root
      end

      # Returns relative paths of files changed inside the sandbox vs the original.
      def changed_files
        return [] unless @setup_done

        find_files(@root).each_with_object([]) do |abs_path, changed|
          rel       = abs_path.sub("#{@root}/", "")
          orig      = File.join(@source_root, rel)
          changed << rel if !File.exist?(orig) || File.read(abs_path) != File.read(orig)
        rescue StandardError
          next
        end
      end

      # Files present in source but deleted in sandbox.
      def deleted_files
        return [] unless @setup_done

        find_files(@source_root).each_with_object([]) do |abs_path, deleted|
          rel = abs_path.sub("#{@source_root}/", "")
          deleted << rel unless File.exist?(File.join(@root, rel))
        end
      end

      # Copy changed sandbox files back to target (defaults to source_root).
      # @param target     [String]  destination directory
      # @param only_files [Array]   restrict to specific relative paths
      # @return [Array<String>] list of relative paths copied
      def sync_back!(target: nil, only_files: nil)
        raise "Sandbox not set up" unless @setup_done

        dest    = File.expand_path(target || @source_root)
        to_copy = only_files || changed_files

        to_copy.each do |rel|
          src  = File.join(@root, rel)
          dst  = File.join(dest, rel)
          FileUtils.mkdir_p(File.dirname(dst))
          FileUtils.cp(src, dst)
        end

        to_copy
      end

      # Remove the temporary directory.
      def teardown!
        return unless @root && File.directory?(@root)

        FileUtils.rm_rf(@root)
        @root       = nil
        @setup_done = false
      end

      # Run a block inside the sandbox, then teardown.
      def use
        setup!
        yield self
      ensure
        teardown!
      end

      private

      def copy_tree(src, dst)
        Dir.foreach(src) do |entry|
          next if entry.start_with?(".")
          next if IGNORED_DIRS.include?(entry)

          src_path = File.join(src, entry)
          dst_path = File.join(dst, entry)

          if File.directory?(src_path)
            FileUtils.mkdir_p(dst_path)
            copy_tree(src_path, dst_path)
          else
            FileUtils.cp(src_path, dst_path)
          end
        end
      end

      def find_files(dir)
        files = []
        Dir.glob(File.join(dir, "**", "*"), File::FNM_DOTMATCH).each do |path|
          next if File.directory?(path)
          next if IGNORED_DIRS.any? { |d| path.include?("/#{d}/") }

          files << path
        end
        files
      end
    end
  end
end
