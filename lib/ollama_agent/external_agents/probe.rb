# frozen_string_literal: true

require "open3"

require_relative "argv_interp"
require_relative "env_helpers"

module OllamaAgent
  module ExternalAgents
    # Resolves executables and optional --version for registry entries.
    # rubocop:disable Metrics/ModuleLength -- CLI resolution + Anthropic transport in one module
    module Probe
      # rubocop:disable Metrics/ClassLength -- single helper singleton for PATH + API probes
      class << self
        # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- branching PATH vs env vs Anthropic
        def resolve_executable(agent)
          return resolve_anthropic_executable(agent) if agent["transport"].to_s == "anthropic_api"

          env_key = agent["env_path"]
          if env_key && EnvHelpers.env_present?(env_key)
            path = File.expand_path(ENV[env_key].to_s.strip)
            return path if File.file?(path)
          end

          name = agent["binary"].to_s
          return nil if name.empty?

          resolved = resolve_via_command_v(name)
          return resolved if resolved

          resolve_via_path_walk(name)
        end
        # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

        # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
        def fetch_status(agent)
          cache_key = status_cache_key(agent)
          cached = status_cache[cache_key]
          return cached.dup if cached

          exe = resolve_executable(agent)
          if exe.nil?
            status = {
              "id" => agent["id"].to_s,
              "available" => false,
              "path" => nil,
              "version" => nil,
              "capabilities" => agent["capabilities"] || [],
              "error" => agent_unavailable_message(agent)
            }
            status_cache[cache_key] = status
            return status.dup
          end

          status = {
            "id" => agent["id"].to_s,
            "available" => true,
            "path" => exe,
            "version" => capture_version(agent, exe),
            "capabilities" => agent["capabilities"] || [],
            "error" => nil
          }
          status_cache[cache_key] = status
          status.dup
        end
        # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

        # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
        def capture_version(agent, exe)
          return anthropic_model_label(agent) if anthropic_executable?(agent, exe)

          argv_templ = agent["version_argv"]
          return nil unless argv_templ.is_a?(Array) && !argv_templ.empty?

          argv = ArgvInterp.expand(argv_templ, "binary" => exe, "task_file" => "", "root" => "")
          out, err, status = Open3.capture3(*argv)
          return nil unless status.success?

          s = out.to_s.strip
          s = err.to_s.strip if s.empty?
          return nil if s.empty?

          s.lines.first&.strip
        rescue StandardError
          nil
        end
        # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

        # rubocop:disable Metrics/MethodLength
        def print_table(registry, io: $stdout)
          io.puts "id\tok?\tpath\tversion\tcapabilities"
          registry.agents.each do |a|
            r = fetch_status(a)
            io.puts [
              r["id"],
              r["available"] ? "yes" : "no",
              r["path"] || "-",
              (r["version"] || "-").to_s[0, 80],
              (r["capabilities"] || []).join(",")
            ].join("\t")
          end
        end
        # rubocop:enable Metrics/MethodLength

        def clear_cache!
          status_cache.clear
        end

        def status_cache_key(agent)
          env_key = agent["env_path"].to_s
          env_val = env_key.empty? ? "" : ENV.fetch(env_key, "")
          [
            agent["id"].to_s,
            agent["binary"].to_s,
            env_key,
            env_val
          ].join("|")
        end

        private

        def resolve_anthropic_executable(agent)
          return nil unless EnvHelpers.env_present?("ANTHROPIC_API_KEY")

          "anthropic-api:#{agent["id"]}"
        end

        def anthropic_executable?(agent, exe)
          agent["transport"].to_s == "anthropic_api" && exe.to_s.start_with?("anthropic-api:")
        end

        def anthropic_model_label(agent)
          (agent["model"] || ENV.fetch("OLLAMA_AGENT_ANTHROPIC_MODEL", "claude-opus-4-7")).to_s
        end

        def agent_unavailable_message(agent)
          return "ANTHROPIC_API_KEY is not set" if agent["transport"].to_s == "anthropic_api"

          "executable not found (set #{agent["env_path"] || "PATH"})"
        end

        # POSIX `command -v` when /usr/bin/command exists; rescues ENOENT when `command` is shell-only.
        def resolve_via_command_v(name)
          out, status = Open3.capture2("command", "-v", name)
          return out.strip if status.success? && !out.to_s.strip.empty?

          nil
        rescue Errno::ENOENT
          nil
        end

        def resolve_via_path_walk(name)
          ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).each do |dir|
            next if dir.empty?

            abs = File.join(dir, name)
            return abs if File.file?(abs) && File.executable?(abs)
          end
          nil
        end

        def status_cache
          @status_cache ||= {}
        end
      end
      # rubocop:enable Metrics/ClassLength
    end
    # rubocop:enable Metrics/ModuleLength
  end
end
