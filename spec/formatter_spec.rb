# frozen_string_literal: true

require_relative "spec_helper"
require "stringio"
require "railway_cli/formatter"
require "railway_cli/error"
require "railway_cli/commands/whoami"

class FormatterTest < Minitest::Test
  include FakeHttp

  def test_table
    out = RailwayCli::Formatter.table([{ name: "svc_example", id: "1" }, { "name" => "x", "id" => "22" }], %i[name id])
    assert_equal "NAME         ID\nsvc_example  1\nx            22", out
  end

  def test_kv
    assert_equal "a    1\nbbb  2", RailwayCli::Formatter.kv(a: 1, bbb: 2)
  end

  def test_envelopes
    assert_equal({ "ok" => true, "command" => "c", "data" => [1] },
                 JSON.parse(RailwayCli::Formatter.envelope("c", [1])))
    err = RailwayCli::ApiError.new("m", code: "C", trace_id: "t")
    assert_equal({ "ok" => false, "error" => { "message" => "m", "code" => "C", "traceId" => "t" } },
                 JSON.parse(RailwayCli::Formatter.error_envelope(err)))
  end

  def test_whoami_probe_order_and_types
    na = { errors: [{ message: "Not Authorized" }] }
    t, calls = fake_transport(
      resp(200, na),
      resp(200, { data: { apiToken: { workspaces: [{ id: "ws_example", name: "Example" }] } } }),
      resp(200, na), resp(200, na),
      resp(200, { data: { projectToken: { projectId: "proj_example", environmentId: "env_example" } } })
    )
    env = { "RAILWAY_PAT_ACCOUNT" => "a-placeholder", "RAILWAY_PAT_PROJECT" => "p-placeholder" }
    r = RailwayCli::Commands::Whoami.report(env, transport: t)
    assert_equal "workspace", r["bearer"]["type"]
    assert_equal "project", r["project"]["type"]
    assert_equal "RAILWAY_PAT_PROJECT", r["project"]["source"]
    ops = calls.map { |c| c[:body]["query"][/query (\w+)/, 1] }
    assert_equal %w[Me ApiToken Me ApiToken ProjectToken], ops
    assert_equal "Bearer a-placeholder", calls[0][:headers]["Authorization"]
    assert_equal "p-placeholder", calls[2][:headers]["Project-Access-Token"]
  end

  def test_whoami_account_and_not_set_json
    t, = fake_transport(resp(200, { data: { me: { id: "00000000-0000-0000-0000-000000000000", name: "U", email: "user@example.com" } } }))
    out = StringIO.new
    RailwayCli::Commands::Whoami.run({ "RAILWAY_PAT_ACCOUNT" => "a-placeholder" }, json: true, out: out, transport: t)
    data = JSON.parse(out.string)["data"]
    assert_equal "account", data["bearer"]["type"]
    assert_equal "user@example.com", data["bearer"]["identity"]["email"]
    assert_equal "not set", data["project"]["status"]
    refute_includes out.string, "a-placeholder"
  end
end
