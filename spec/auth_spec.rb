# frozen_string_literal: true

require_relative "spec_helper"
require "railway_cli/auth"

class AuthTest < Minitest::Test
  BOTH = { "RAILWAY_PAT_ACCOUNT" => "acct-placeholder", "RAILWAY_PAT_PROJECT" => "proj-placeholder" }.freeze

  def test_prefers_bearer
    c = RailwayCli::Auth.pick(BOTH)
    assert_equal :bearer, c.kind
    assert_equal "RAILWAY_PAT_ACCOUNT", c.source
  end

  def test_project_token_flag
    c = RailwayCli::Auth.pick(BOTH, project_token: true)
    assert_equal :project, c.kind
    assert_equal "RAILWAY_PAT_PROJECT", c.source
  end

  def test_project_only
    c = RailwayCli::Auth.pick({ "RAILWAY_TOKEN" => "p" })
    assert_equal [:project, "RAILWAY_TOKEN"], [c.kind, c.source]
  end

  def test_fallback_and_blank
    c = RailwayCli::Auth.pick({ "RAILWAY_PAT_ACCOUNT" => "  ", "RAILWAY_API_TOKEN" => "b" })
    assert_equal "RAILWAY_API_TOKEN", c.source
  end

  def test_none_raises
    assert_raises(RailwayCli::AuthError) { RailwayCli::Auth.pick({}) }
  end

  def test_headers_per_kind
    assert_equal({ "Authorization" => "Bearer t" }, RailwayCli::Credential.new(:bearer, "t", "K").headers)
    assert_equal({ "Project-Access-Token" => "t" }, RailwayCli::Credential.new(:project, "t", "K").headers)
  end

  def test_inspect_hides_token
    c = RailwayCli::Credential.new(:bearer, "secret-placeholder-value", "RAILWAY_PAT_ACCOUNT")
    refute_includes c.inspect, "secret-placeholder-value"
    refute_includes c.to_s, "secret-placeholder-value"
    refute_includes "#{c}", "secret-placeholder-value"
  end

  def test_redaction_in_error
    RailwayCli::Redact.register("secret-placeholder-value")
    e = RailwayCli::ApiError.new("bad token secret-placeholder-value here")
    assert_equal "bad token [REDACTED] here", e.message
  ensure
    RailwayCli::Redact.reset!
  end

  def test_redact_call_explicit_tokens
    assert_equal "a [REDACTED] b", RailwayCli::Redact.call("a xyz b", ["xyz"])
  end
end
