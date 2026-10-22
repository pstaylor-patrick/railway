# frozen_string_literal: true

require_relative "spec_helper"
require "railway_cli/auth"
require "railway_cli/client"
require "railway_cli/resolver"

class ResolverTest < Minitest::Test
  include FakeHttp

  ITEMS = [
    { "id" => "proj_example", "name" => "web" },
    { "id" => "proj_example2", "name" => "Api" },
    { "id" => "proj_example3", "name" => "dup" },
    { "id" => "proj_example4", "name" => "DUP" },
    { "id" => "proj_example5", "name" => "Dup" }
  ].freeze

  def pick(q) = RailwayCli::Resolver.pick(ITEMS, q, "project")

  def test_by_id
    assert_equal "web", pick("proj_example")["name"]
  end

  def test_exact_name_wins_over_case_insensitive
    assert_equal "proj_example4", pick("DUP")["id"]
  end

  def test_case_insensitive_fallback
    assert_equal "proj_example2", pick("api")["id"]
  end

  def test_ambiguous_lists_candidates
    e = assert_raises(RailwayCli::UsageError) { pick("dUp") }
    assert_includes e.message, "ambiguous"
    assert_includes e.message, "proj_example3"
    assert_includes e.message, "proj_example5"
  end

  def test_no_match_and_missing
    assert_includes assert_raises(RailwayCli::UsageError) { pick("nope") }.message, "candidates"
    assert_includes assert_raises(RailwayCli::UsageError) { pick(nil) }.message, "--project is required"
  end

  PROJECT = {
    "id" => "proj_example", "name" => "web",
    "environments" => { "edges" => [{ "node" => { "id" => "env_example", "name" => "production" } }] },
    "services" => { "edges" => [{ "node" => { "id" => "svc_example", "name" => "api", "serviceInstances" => { "edges" => [] } } }] }
  }.freeze

  def test_project_token_scope_needs_no_flags
    t, calls = fake_transport(
      resp(200, { data: { projectToken: { projectId: "proj_example", environmentId: "env_example" } } }),
      resp(200, { data: { project: PROJECT } })
    )
    cred = RailwayCli::Credential.new(:project, "tok-placeholder", "RAILWAY_PAT_PROJECT")
    r = RailwayCli::Resolver.new(RailwayCli::Client.new(credential: cred, transport: t), {})
    assert_equal "web", r.project["name"]
    assert_equal "env_example", r.environment["id"]
    assert_equal({ "id" => "proj_example" }, calls.last[:body]["variables"])
  end

  def test_bearer_resolves_name_through_paginated_projects
    t, calls = fake_transport(
      resp(200, { data: { projects: { edges: [{ node: { id: "proj_other", name: "x" } }],
                                      pageInfo: { hasNextPage: true, endCursor: "c1" } } } }),
      resp(200, { data: { projects: { edges: [{ node: { id: "proj_example", name: "web" } }],
                                      pageInfo: { hasNextPage: false } } } }),
      resp(200, { data: { project: PROJECT } })
    )
    cred = RailwayCli::Credential.new(:bearer, "tok-placeholder", "RAILWAY_PAT_ACCOUNT")
    r = RailwayCli::Resolver.new(RailwayCli::Client.new(credential: cred, transport: t),
                                 { project: "web", env: "PRODUCTION", service: "api" })
    assert_equal "proj_example", r.project["id"]
    assert_equal "c1", calls[1][:body]["variables"]["after"]
    assert_equal "env_example", r.environment["id"]
    assert_equal "svc_example", r.service["id"]
  end
end
