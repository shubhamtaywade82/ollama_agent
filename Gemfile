# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in ollama_agent.gemspec
gemspec

gem "ollama-client"

gem "irb"
gem "rake", "~> 13.0"

gem "rspec", "~> 3.0"

gem "rubocop", "~> 1.21"
# parallel 2.x requires Ruby >= 3.3; CI still tests 3.2.x per gemspec.
gem "parallel", "< 2"
gem "rubocop-rake", require: false
gem "rubocop-rspec", require: false

# Optional static analysis context for self_review / improve (see README)
gem "ruby_mastery", github: "shubhamtaywade82/ruby_mastery"
