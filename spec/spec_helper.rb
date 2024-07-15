# frozen_string_literal: true

require "dotenv/load"
require "debug"
require "mongodb_meilisearch"

module Helpers
  def supress_output
    supress_stdout
    supress_stderr
  end

  def unsupress_output
    unsupress_stdout if @original_stdout
    unsupress_stderr if @original_stderr
  end

  def supress_stdout
    return if @original_stdout
    @original_stdout = $stdout
    $stdout = File.open(File::NULL, "w")
  end

  def supress_stderr
    return if @original_stderr # already supressed
    @original_stderr = $stderr
    $stderr = File.open(File::NULL, "w")
  end

  def unsupress_stderr
    return unless @original_stderr
    $stderr = @original_stderr
    @original_stderr = nil
  end

  def unsupress_stdout
    return unless @original_stdout
    $stdout = @original_stdout
    @original_stdout = nil
  end
end

RSpec.configure do |config|
  config.include Helpers
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
  config.after(:all) do
    unsupress_output # no-op if none was supressed
  end
end
