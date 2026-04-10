# frozen_string_literal: true

require "dotenv"

module OllamaAgent
  # The ollama-client gem runs +Dotenv.overload+ against the current working directory +.env+.
  # When a global config file exists (XDG path or +OLLAMA_AGENT_DOTENV_PATH+), restore the
  # environment from before that load and apply only that file so API keys are not picked up
  # from arbitrary project trees.
  module GlobalDotenv
    module_function

    def reconcile_after_ollama_client!(snapshot)
      return if use_local_dotenv?
      return unless (path = resolved_path) && File.file?(path)

      ENV.replace(snapshot)
      Dotenv.overload(path)
    end

    def use_local_dotenv?
      ENV["OLLAMA_AGENT_USE_LOCAL_DOTENV"] == "1"
    end

    def resolved_path
      custom = ENV["OLLAMA_AGENT_DOTENV_PATH"].to_s.strip
      return File.expand_path(custom) unless custom.empty?

      File.join(xdg_config_home, "ollama_agent", ".env")
    end

    def xdg_config_home
      base = ENV["XDG_CONFIG_HOME"].to_s.strip
      return File.expand_path(base) unless base.empty?

      File.expand_path(File.join(Dir.home, ".config"))
    end
  end
end
