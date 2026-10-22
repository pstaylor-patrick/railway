# frozen_string_literal: true

require_relative "spec_helper"
require "stringio"
require "railway_cli/auth"
require "railway_cli/client"
require "railway_cli/dashboard"
require "railway_cli/commands/variables"

class VariablesTest < Minitest::Test
  include FakeHttp

  V = RailwayCli::Commands::Variables
  CRED = RailwayCli::Credential.new(:bearer, "tok-placeholder", "RAILWAY_PAT_ACCOUNT")

  PROJECT = {
    "id" => "proj_example", "name" => "web",
    "environments" => { "edges" => [{ "node" => { "id" => "env_example", "name" => "production" } },
                                    { "node" => { "id" => "env_staging", "name" => "staging" } }] },
    "services" => { "edges" => [{ "node" => { "id" => "svc_example", "name" => "api", "serviceInstances" => { "edges" => [] } } }] }
  }.freeze
  PROJECTS_PAGE = { data: { projects: { edges: [{ node: { id: "proj_example", name: "web", workspace: { id: "w", name: "ws" } } }],
                                        pageInfo: { hasNextPage: false } } } }.freeze

  def ctx(transport, opts = {}, args = [])
    client = RailwayCli::Client.new(credential: CRED, transport: transport)
    @out = StringIO.new
    RailwayCli::Commands::Context.new(client: client, resolver: RailwayCli::Resolver.new(client, opts),
                                      opts: opts, args: args, out: @out)
  end

  def test_mask_rules
    assert_equal "ab****", RailwayCli::Mask.call("abcdefghij")
    assert_equal "****", RailwayCli::Mask.call("short")
    assert_equal "****", RailwayCli::Mask.call("")
    assert_equal "****", RailwayCli::Mask.call(nil)
  end

  def test_dashboard_url
    assert_equal "https://railway.com/project/proj_example/service/svc_example?environmentId=env_example",
                 RailwayCli::Dashboard.url("proj_example", "env_example", "svc_example")
    assert_equal "https://railway.com/project/proj_example?environmentId=env_example",
                 RailwayCli::Dashboard.url("proj_example", "env_example")
  end

  def test_parse_pairs
    assert_equal({ "A" => "1", "B" => "x=y", "C" => "" }, V.parse_pairs(%w[A=1 B=x=y C=]))
  end

  def test_parse_stdin_marker
    assert_equal({ "SECRET" => "from-stdin", "A" => "1" }, V.parse_pairs(%w[SECRET=- A=1], stdin: StringIO.new("from-stdin\n")))
  end

  def test_parse_rejects_bad_input
    assert_raises(RailwayCli::UsageError) { V.parse_pairs([]) }
    assert_raises(RailwayCli::UsageError) { V.parse_pairs(%w[NOEQUALS]) }
    assert_raises(RailwayCli::UsageError) { V.parse_pairs(%w[=v]) }
    assert_raises(RailwayCli::UsageError) { V.parse_pairs(%w[A=- B=-], stdin: StringIO.new("x")) }
  end

  def test_diff_classification
    r = V.classify({ "A" => "1", "B" => "2", "C" => "3" }, { "B" => "2", "C" => "4", "D" => "5" })
    assert_equal %w[A], r["only_a"]
    assert_equal %w[D], r["only_b"]
    assert_equal({ "C" => %w[3 4] }, r["differing"])
  end

  def test_list_masks_by_default
    t, = fake_transport(resp(200, PROJECTS_PAGE), resp(200, { data: { project: PROJECT } }),
                        resp(200, { data: { variables: { "DATABASE_URL" => "postgres://placeholder" } } }))
    V.run(ctx(t, project: "web", env: "production"))
    assert_match(/DATABASE_URL\s+po\*\*\*\*/, @out.string)
    refute_includes @out.string, "placeholder"
  end

  def test_list_reveal
    t, = fake_transport(resp(200, PROJECTS_PAGE), resp(200, { data: { project: PROJECT } }),
                        resp(200, { data: { variables: { "K" => "postgres://placeholder" } } }))
    V.run(ctx(t, project: "web", env: "production", reveal: true))
    assert_includes @out.string, "postgres://placeholder"
  end

  def test_diff_command_masks
    t, calls = fake_transport(resp(200, PROJECTS_PAGE), resp(200, { data: { project: PROJECT } }),
                              resp(200, { data: { variables: { "K" => "value-aaaaaa", "A" => "1" } } }),
                              resp(200, { data: { variables: { "K" => "value-bbbbbb" } } }))
    V.run(ctx(t, { project: "web", env: "production", env2: "staging" }, ["diff"]))
    assert_includes @out.string, "only in production: A"
    assert_includes @out.string, "differs K: production=va**** staging=va****"
    assert_equal "env_staging", calls.last[:body]["variables"]["environmentId"]
  end

  def test_set_single_uses_variable_upsert
    t, calls = fake_transport(resp(200, PROJECTS_PAGE), resp(200, { data: { project: PROJECT } }),
                              resp(200, { data: { variableUpsert: true } }))
    V.run(ctx(t, { project: "web", env: "production", service: "api", skip_deploys: true }, %w[set K=v]))
    body = calls.last[:body]
    assert_includes body["query"], "variableUpsert"
    assert_equal({ "projectId" => "proj_example", "environmentId" => "env_example", "serviceId" => "svc_example",
                   "skipDeploys" => true, "name" => "K", "value" => "v" }, body["variables"]["input"])
  end

  def test_set_many_uses_collection_upsert
    t, calls = fake_transport(resp(200, PROJECTS_PAGE), resp(200, { data: { project: PROJECT } }),
                              resp(200, { data: { variableCollectionUpsert: true } }))
    V.run(ctx(t, { project: "web", env: "production" }, %w[set A=1 B=2]))
    body = calls.last[:body]
    assert_includes body["query"], "variableCollectionUpsert"
    assert_equal({ "A" => "1", "B" => "2" }, body["variables"]["input"]["variables"])
    refute_includes @out.string, "1"
  end
end
