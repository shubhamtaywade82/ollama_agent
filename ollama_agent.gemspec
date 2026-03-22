# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength

require_relative "lib/ollama_agent/version"

Gem::Specification.new do |spec|
  spec.name = "ollama_agent"
  spec.version = OllamaAgent::VERSION
  spec.authors = ["Shubham Taywade"]
  spec.email = ["shubhamtaywade82@gmail.com"]

  spec.summary = "CLI agent that applies small code patches using Ollama tool calling."
  spec.description = "Use natural language to read files, search the tree, " \
                     "and apply unified diffs via a local Ollama model."
  spec.homepage = "https://github.com/shubhamtaywade82/ollama_agent"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .github/ .rubocop.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "dotenv", "~> 2.8"
  spec.add_dependency "ollama-client", "~> 1.1"
  spec.add_dependency "prism", "~> 1.0"
  spec.add_dependency "thor", "~> 1.2"
  spec.add_dependency "tty-markdown", "~> 0.7"

  # rubocop:disable Gemspec/DevelopmentDependencies
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  # rubocop:enable Gemspec/DevelopmentDependencies
end
# rubocop:enable Metrics/BlockLength
