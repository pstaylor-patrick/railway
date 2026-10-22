# frozen_string_literal: true

require_relative "spec_helper"
require "stringio"
require "open3"
require "railway_cli/confirm"
require "railway_cli/auth"
require "railway_cli/client"
require "railway_cli/commands/environment"
require "railway_cli/commands/variables"

class ConfirmTest < Minitest::Test
  include FakeHttp

  Confirm = RailwayCli::Confirm
  Refused = RailwayCli::ConfirmRefused

  # An input that fails the test if read.
  class NoRead
    def gets = raise("input must not be read")
    def tty? = false
  end

  def test_matching_flag_passes_without_reading_input
    assert Confirm.require!(expected: "tmp-x", kind: "environment", flag: "tmp-x", input: NoRead.new, tty: true)
  end

  def test_wrong_flag_refuses
    e = assert_raises(Refused) { Confirm.require!(expected: "tmp-x", kind: "environment", flag: "tmp-y", input: NoRead.new, tty: true) }
    assert_includes e.message, "does not match"
  end

  def test_no_tty_and_no_flag_refuses
    e = assert_raises(Refused) { Confirm.require!(expected: "tmp-x", kind: "environment", flag: nil, input: NoRead.new, tty: false) }
    assert_includes e.message, "--confirm"
  end

  def test_tty_matching_typed_name_passes
    out = StringIO.new
    assert Confirm.require!(expected: "tmp-x", kind: "environment", flag: nil, input: StringIO.new("tmp-x\n"), output: out, tty: true)
    assert_includes out.string, "tmp-x"
  end

  def test_tty_mismatch_refuses
    assert_raises(Refused) do
      Confirm.require!(expected: "tmp-x", kind: "environment", flag: nil, input: StringIO.new("tmp\n"), output: StringIO.new, tty: true)
    end
  end

  def test_tty_eof_refuses
    assert_raises(Refused) do
      Confirm.require!(expected: "tmp-x", kind: "environment", flag: nil, input: StringIO.new(""), output: StringIO.new, tty: true)
    end
  end

  def test_default_tty_detection_from_input
    assert_raises(Refused) { Confirm.require!(expected: "tmp-x", kind: "environment", flag: nil, input: StringIO.new("tmp-x\n")) }
  end

  CRED = RailwayCli::Credential.new(:bearer, "tok-placeholder", "RAILWAY_PAT_ACCOUNT")
  PROJECT = { "id" => "proj_example", "name" => "web",
              "environments" => { "edges" => [{ "node" => { "id" => "env_example", "name" => "tmp-x" } }] },
              "services" => { "edges" => [] } }.freeze
  PROJECTS_PAGE = { data: { projects: { edges: [{ node: { id: "proj_example", name: "web" } }], pageInfo: { hasNextPage: false } } } }.freeze

  def ctx(transport, opts, args)
    client = RailwayCli::Client.new(credential: CRED, transport: transport, sleeper: ->(_) {})
    RailwayCli::Commands::Context.new(client: client, resolver: RailwayCli::Resolver.new(client, opts),
                                      opts: opts, args: args, out: StringIO.new)
  end

  def test_env_delete_unknown_name_fails_before_confirm
    t, calls = fake_transport(resp(200, WORKSPACES_PAGE), resp(200, PROJECTS_PAGE), resp(200, { data: { project: PROJECT } }))
    assert_raises(RailwayCli::UsageError) { RailwayCli::Commands::Environment.run(ctx(t, { project: "web" }, %w[delete nope])) }
    refute(calls.any? { |c| c[:body]["query"].include?("mutation") })
  end

  def test_env_delete_without_confirm_and_no_tty_mutates_nothing
    t, calls = fake_transport(resp(200, WORKSPACES_PAGE), resp(200, PROJECTS_PAGE), resp(200, { data: { project: PROJECT } }))
    old = $stdin
    $stdin = StringIO.new("tmp-x\n") # not a TTY
    assert_raises(Refused) { RailwayCli::Commands::Environment.run(ctx(t, { project: "web" }, %w[delete tmp-x])) }
  ensure
    $stdin = old
    refute(calls.any? { |c| c[:body]["query"].include?("mutation") })
  end

  def test_env_delete_with_confirm_mutates
    t, calls = fake_transport(resp(200, WORKSPACES_PAGE), resp(200, PROJECTS_PAGE), resp(200, { data: { project: PROJECT } }),
                              resp(200, { data: { environmentDelete: true } }))
    assert_equal 0, RailwayCli::Commands::Environment.run(ctx(t, { project: "web", confirm: "tmp-x" }, %w[delete tmp-x]))
    assert_includes calls.last[:body]["query"], "environmentDelete"
    assert_equal({ "id" => "env_example" }, calls.last[:body]["variables"])
  end

  def test_vars_delete_missing_key_fails_before_confirm
    t, = fake_transport(resp(200, WORKSPACES_PAGE), resp(200, PROJECTS_PAGE), resp(200, { data: { project: PROJECT } }),
                        resp(200, { data: { variables: { "OTHER" => "x" } } }))
    assert_raises(RailwayCli::UsageError) do
      RailwayCli::Commands::Variables.run(ctx(t, { project: "web", env: "tmp-x", confirm: "KEY" }, %w[delete KEY]))
    end
  end

  def test_yes_flag_is_usage_error
    bin = File.expand_path("../bin/railway", __dir__)
    _out, _err, status = Open3.capture3("ruby", bin, "env", "delete", "tmp-x", "--project", "web", "--yes", stdin_data: "")
    assert_equal 2, status.exitstatus
  end

  def test_exit_codes
    assert_equal 3, RailwayCli.exit_code(Refused.new("no"))
    assert_equal 2, RailwayCli.exit_code(RailwayCli::UsageError.new("no such environment"))
    assert_equal 1, RailwayCli.exit_code(RailwayCli::ApiError.new("boom"))
  end
end
