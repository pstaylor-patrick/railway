# frozen_string_literal: true

require_relative "spec_helper"
require "stringio"
require "railway_cli/auth"
require "railway_cli/client"
%w[projects status deployments domains rate].each { |c| require "railway_cli/commands/#{c}" }

class ReadCommandsTest < Minitest::Test
  include FakeHttp

  CRED = RailwayCli::Credential.new(:bearer, "tok-placeholder", "RAILWAY_PAT_ACCOUNT")

  PROJECT = {
    "id" => "proj_example", "name" => "web",
    "environments" => { "edges" => [{ "node" => { "id" => "env_example", "name" => "production" } }] },
    "services" => { "edges" => [{ "node" => {
      "id" => "svc_example", "name" => "api",
      "serviceInstances" => { "edges" => [{ "node" => {
        "environmentId" => "env_example",
        "latestDeployment" => { "id" => "dep1", "status" => "SUCCESS", "createdAt" => "2026-01-01T00:00:00Z" },
        "domains" => { "serviceDomains" => [{ "domain" => "api.example.com" }], "customDomains" => [] }
      } }] }
    } }] }
  }.freeze

  PROJECTS_PAGE = { data: { projects: { edges: [{ node: { id: "proj_example", name: "web", workspace: { id: "w", name: "ws" } } }],
                                        pageInfo: { hasNextPage: false } } } }.freeze

  def ctx(transport, opts = {})
    client = RailwayCli::Client.new(credential: CRED, transport: transport)
    @out = StringIO.new
    RailwayCli::Commands::Context.new(client: client, resolver: RailwayCli::Resolver.new(client, opts),
                                      opts: opts, args: [], out: @out)
  end

  def test_projects_table
    t, = fake_transport(resp(200, WORKSPACES_PAGE), resp(200, PROJECTS_PAGE))
    assert_equal 0, RailwayCli::Commands::Projects.run(ctx(t))
    lines = @out.string.lines
    assert_match(/\ANAME\s+ID\s+WORKSPACE/, lines[0])
    assert_match(/\Aweb\s+proj_example\s+ws/, lines[1])
  end

  def test_projects_json_envelope
    t, = fake_transport(resp(200, WORKSPACES_PAGE), resp(200, PROJECTS_PAGE))
    RailwayCli::Commands::Projects.run(ctx(t, json: true))
    d = JSON.parse(@out.string)
    assert d["ok"]
    assert_equal "projects", d["command"]
  end

  def test_status_defaults_to_production
    t, = fake_transport(resp(200, WORKSPACES_PAGE), resp(200, PROJECTS_PAGE), resp(200, { data: { project: PROJECT } }))
    RailwayCli::Commands::Status.run(ctx(t, project: "web"))
    assert_includes @out.string, "environment: production"
    assert_match(/api\s+SUCCESS\s+2026-01-01T00:00:00Z\s+api\.example\.com/, @out.string)
  end

  def test_deployments_respects_limit_and_input
    edges = (1..3).map { |i| { node: { id: "dep#{i}", status: "SUCCESS", createdAt: "t" } } }
    t, calls = fake_transport(resp(200, WORKSPACES_PAGE), resp(200, PROJECTS_PAGE), resp(200, { data: { project: PROJECT } }),
                              resp(200, { data: { deployments: { edges: edges, pageInfo: { hasNextPage: true, endCursor: "c" } } } }))
    RailwayCli::Commands::Deployments.run(ctx(t, project: "web", env: "production", service: "api", limit: 2, json: true))
    assert_equal %w[dep1 dep2], JSON.parse(@out.string)["data"].map { |d| d["id"] }
    assert_equal({ "projectId" => "proj_example", "environmentId" => "env_example", "serviceId" => "svc_example" },
                 calls.last[:body]["variables"]["input"])
  end

  def test_domains_lists_service_domains
    t, = fake_transport(resp(200, WORKSPACES_PAGE), resp(200, PROJECTS_PAGE), resp(200, { data: { project: PROJECT } }))
    RailwayCli::Commands::Domains.run(ctx(t, project: "web", env: "production"))
    assert_match(/api\s+api\.example\.com\s+service/, @out.string)
  end

  def test_rate_falls_back_to_api_token_for_workspace_tokens
    t, calls = fake_transport(resp(200, { errors: [{ message: "Not Authorized" }] }),
                              resp(200, { data: { apiToken: { workspaces: [] } } }, { "X-RateLimit-Remaining" => "7" }))
    RailwayCli::Commands::Rate.run(ctx(t))
    assert_includes calls.last[:body]["query"], "apiToken"
    assert_match(/remaining\s+7/, @out.string)
  end

  def test_projects_lists_each_workspace_and_dedupes
    two = { data: { me: { workspaces: [{ id: "ws_a" }, { id: "ws_b" }] } } }
    t, calls = fake_transport(resp(200, two), resp(200, WORKSPACES_PAGE), resp(200, PROJECTS_PAGE), resp(200, WORKSPACES_PAGE), resp(200, PROJECTS_PAGE))
    RailwayCli::Commands::Projects.run(ctx(t, json: true))
    assert_equal %w[ws_a ws_b], calls[1..].map { |c| c[:body]["variables"]["workspaceId"] }
    assert_equal 1, JSON.parse(@out.string)["data"].size
  end

  def test_projects_falls_back_to_api_token_workspaces
    denied = { errors: [{ message: "Not Authorized" }] }
    t, calls = fake_transport(resp(200, denied), resp(200, { data: { apiToken: { workspaces: [{ id: "ws_a" }] } } }),
                              resp(200, WORKSPACES_PAGE), resp(200, PROJECTS_PAGE))
    RailwayCli::Commands::Projects.run(ctx(t))
    assert_equal "ws_a", calls[2][:body]["variables"]["workspaceId"]
  end
end
