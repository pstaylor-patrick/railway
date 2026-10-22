# frozen_string_literal: true

require_relative "spec_helper"
require "tmpdir"
require "railway_cli/env"

class EnvTest < Minitest::Test
  def with_file(text)
    Dir.mktmpdir do |d|
      p = File.join(d, ".env")
      File.write(p, text)
      yield p
    end
  end

  def test_parses_and_strips
    with_file("# c\n\nexport A=\"one\"\nB='two'\nC=three=3\n") do |p|
      env = RailwayCli::Env.load(p, {})
      assert_equal({ "A" => "one", "B" => "two", "C" => "three=3" }, env)
    end
  end

  def test_does_not_override_exported
    with_file("A=fromfile\n") do |p|
      env = RailwayCli::Env.load(p, { "A" => "exported" })
      assert_equal "exported", env["A"]
    end
  end

  def test_missing_file_is_noop
    assert_equal({}, RailwayCli::Env.load("/nonexistent/.env", {}))
  end
end
