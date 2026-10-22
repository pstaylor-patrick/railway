# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/railway_cli/version"

class VersionTest < Minitest::Test
  def test_version_is_semver
    assert_match(/\A\d+\.\d+\.\d+\z/, RailwayCli::VERSION)
  end
end
