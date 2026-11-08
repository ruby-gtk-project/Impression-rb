# frozen_string_literal: true

# Config for development dependencies of this library
# i.e., not configured by this library
#
# SimpleCov & related config (must run BEFORE any other requires)
# NOTE: Gemfiles for non-coverage appraisals may not have kettle-soup-cover.
#       The rescue LoadError handles that scenario.
begin
  require "kettle-soup-cover"
  if Kettle::Soup::Cover::DO_COV
    # Requiring simplecov loads the project-local `.simplecov`.
    require "simplecov"
    require "kettle/soup/cover/config"
    SimpleCov.start
  end
rescue LoadError => error
  # check the error message and re-raise when unexpected
  raise error unless error.message.include?("kettle")
end

# External RSpec & related config
begin
  require "kettle/test/rspec"
  # `kettle/test/rspec` installs harness helpers documented in spec/README.md.
rescue LoadError => error
  # The flake's devShell deliberately does not bundle the kettle-test/
  # kettle-family stack (it is kettle-jem's own dev/release tooling, not a
  # runtime dependency of the port) so the dev shell's own printed spec
  # command -- `ruby -e '...RSpec::Core::Runner.run(...)'` -- can still run
  # to completion instead of dying on this require before a single example
  # loads. Outside that shell (the root Gemfile, CI), the gem is present and
  # this branch never runs.
  raise error unless error.message.include?("kettle")

  warn "kettle-test/rspec not available (#{error.message}); running without its harness helpers."
end

# This library
require "impression/rb"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
