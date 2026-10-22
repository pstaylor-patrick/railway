# frozen_string_literal: true

require_relative "spec_helper"
require "stringio"
require "railway_cli/auth"
require "railway_cli/client"
require "railway_cli/commands/deploy"
require "railway_cli/commands/domain"
require "railway_cli/commands/environment"
require "railway_cli/commands/project_write"

class WriteCommandsTest < Minitest::Test
  include FakeHttp

  C = RailwayCli::Commands
  CRED = RailwayCli::Credential.new(:bearer, "tok-placeholder", "RAILWAY_PAT_ACCOUNT")
  INSTANCES = { "edges" => [{ "node" => { "environmentId" => "env_example" } }] }.freeze
  PROJECT = {
    "id" => "proj_example", "name" => "web",
    "environments" => { "edges" => [{ "node" => { "id" => "env_example", "name" => "production" } }] },
    "services" => { "edges" => [{ "node" => { "id" => "svc_example", "name" => "api", "serviceInstances" => INSTANCES } },
                                { "node" => { "id" => "svc_other", "name" => "worker", "serviceInstances" => INSTANCES } }] }
  }.freeze
  PROJECTS_PAGE = { data: { projects: { edges: [{ node: { id: "proj_example", name: "web", workspace: { id: "ws_example", name: "ws" } } }],
                                        pageInfo: { hasNextPage: false } } } }.freeze

  def ctx(transport, opts = {}, args = [])
    client = RailwayCli::Client.new(credential: CRED, transport: transport, sleeper: ->(_) {})
    @out = StringIO.new
    C::Context.new(client: client, resolver: RailwayCli::Resolver.new(client, opts), opts: opts, args: args, out: @out)
  end

  def project_resps = [resp(200, PROJECTS_PAGE), resp(200, { data: { project: PROJECT } })]

  def test_restart_with_explicit_deployment_skips_lookup
    t, calls = fake_transport(resp(200, { data: { deploymentRestart: true } }))
    assert_equal 0, C::DeploymentAction.for("restart").call(ctx(t, deployment: "dep_example"))
    assert_equal 1, calls.size
    assert_includes calls[0][:body]["query"], "deploymentRestart"
    assert_equal({ "id" => "dep_example" }, calls[0][:body]["variables"])
  end

  def test_redeploy_picks_latest_deployment
    t, calls = fake_transport(*project_resps,
                              resp(200, { data: { deployments: { edges: [{ node: { id: "dep_latest" } }], pageInfo: { hasNextPage: false } } } }),
                              resp(200, { data: { deploymentRedeploy: { id: "dep_new", status: "QUEUED" } } }))
    C::DeploymentAction.for("redeploy").call(ctx(t, project: "web", env: "production", service: "api"))
    assert_equal 1, calls[2][:body]["variables"]["first"]
    assert_equal "svc_example", calls[2][:body]["variables"]["input"]["serviceId"]
    assert_equal({ "id" => "dep_latest" }, calls[3][:body]["variables"])
  end

  def test_action_without_deployment_or_service_is_usage_error
    t, = fake_transport
    assert_raises(RailwayCli::UsageError) { C::DeploymentAction.for("stop").call(ctx(t, project: "web")) }
  end

  def test_unknown_action_rejected
    assert_raises(ArgumentError) { C::DeploymentAction.for("explode") }
  end

  def test_mutation_not_retried_on_rate_limit
    t, calls = fake_transport(resp(429, {}, { "retry-after" => "1" }), resp(200, { data: { deploymentCancel: true } }))
    assert_raises(RailwayCli::RateLimited) { C::DeploymentAction.for("cancel").call(ctx(t, deployment: "dep_example")) }
    assert_equal 1, calls.size
  end

  def test_deploy_service
    t, calls = fake_transport(*project_resps, resp(200, { data: { serviceInstanceDeploy: true } }))
    C::Deploy.run(ctx(t, project: "web", env: "production", service: "api"))
    assert_equal({ "serviceId" => "svc_example", "environmentId" => "env_example" }, calls.last[:body]["variables"])
  end

  def test_deploy_all_triggers_each_service
    t, calls = fake_transport(*project_resps, resp(200, { data: { environmentTriggersDeploy: true } }),
                              resp(200, { data: { environmentTriggersDeploy: true } }))
    C::Deploy.run(ctx(t, project: "web", env: "production", all: true))
    assert_equal %w[svc_example svc_other], calls.drop(2).map { |c| c[:body]["variables"]["input"]["serviceId"] }
  end

  def test_deploy_needs_service_or_all
    t, = fake_transport(*project_resps)
    assert_raises(RailwayCli::UsageError) { C::Deploy.run(ctx(t, project: "web", env: "production")) }
  end

  def test_service_domain_create
    t, calls = fake_transport(*project_resps, resp(200, { data: { serviceDomainCreate: { id: "d", domain: "api-example.up.railway.app" } } }))
    C::Domain.run(ctx(t, { project: "web", env: "production", service: "api" }, ["create"]))
    assert_equal({ "environmentId" => "env_example", "serviceId" => "svc_example" }, calls.last[:body]["variables"]["input"])
  end

  def test_custom_domain_checks_availability_and_prints_records
    created = { id: "d", domain: "app.example.com",
                status: { dnsRecords: [{ recordType: "DNS_RECORD_TYPE_CNAME", fqdn: "app.example.com", requiredValue: "x.up.railway.app" }] } }
    t, calls = fake_transport(*project_resps, resp(200, { data: { customDomainAvailable: { available: true } } }),
                              resp(200, { data: { customDomainCreate: created } }))
    C::Domain.run(ctx(t, { project: "web", env: "production", service: "api", custom: "app.example.com" }, ["create"]))
    assert_includes calls[2][:body]["query"], "customDomainAvailable"
    assert_equal "proj_example", calls[3][:body]["variables"]["input"]["projectId"]
    assert_includes @out.string, "x.up.railway.app"
  end

  def test_custom_domain_unavailable_does_not_mutate
    t, calls = fake_transport(*project_resps, resp(200, { data: { customDomainAvailable: { available: false, message: "taken" } } }))
    assert_raises(RailwayCli::ApiError) do
      C::Domain.run(ctx(t, { project: "web", env: "production", service: "api", custom: "app.example.com" }, ["create"]))
    end
    assert_equal 3, calls.size
  end

  def test_env_create_from_source
    t, calls = fake_transport(*project_resps, resp(200, { data: { environmentCreate: { id: "env_new", name: "tmp" } } }))
    opts = { project: "web", from: "production" }
    C::Environment.run(ctx(t, opts, %w[create tmp]))
    assert_equal({ "projectId" => "proj_example", "name" => "tmp", "sourceEnvironmentId" => "env_example" },
                 calls.last[:body]["variables"]["input"])
    assert_equal "https://railway.com/project/proj_example?environmentId=env_new", opts[:dashboard_url]
  end

  def test_env_create_needs_name
    t, = fake_transport
    assert_raises(RailwayCli::UsageError) { C::Environment.run(ctx(t, { project: "web" }, ["create"])) }
  end

  def test_project_create_with_workspace_name
    t, calls = fake_transport(resp(200, PROJECTS_PAGE), resp(200, { data: { projectCreate: { id: "proj_new", name: "new" } } }))
    opts = { workspace: "ws" }
    C::ProjectWrite.run(ctx(t, opts, %w[create new]))
    assert_equal({ "name" => "new", "workspaceId" => "ws_example" }, calls.last[:body]["variables"]["input"])
    assert_equal "https://railway.com/project/proj_new", opts[:dashboard_url]
  end

  def test_project_create_refuses_project_token
    client = RailwayCli::Client.new(credential: RailwayCli::Credential.new(:project, "p", "RAILWAY_PAT_PROJECT"),
                                    transport: fake_transport.first)
    c = C::Context.new(client: client, resolver: RailwayCli::Resolver.new(client, {}), opts: {}, args: %w[create x], out: StringIO.new)
    assert_raises(RailwayCli::UsageError) { C::ProjectWrite.run(c) }
  end
end
