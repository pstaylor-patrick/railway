# frozen_string_literal: true

require_relative "spec_helper"
require "railway_cli/auth"
require "railway_cli/client"

class ClientTest < Minitest::Test
  include FakeHttp

  CRED = RailwayCli::Credential.new(:bearer, "tok-placeholder", "RAILWAY_PAT_ACCOUNT")

  def client(transport)
    @slept = []
    RailwayCli::Client.new(credential: CRED, transport: transport, sleeper: ->(s) { @slept << s })
  end

  def test_posts_json_with_headers
    t, calls = fake_transport(resp(200, { data: { me: { id: "x" } } }, { "X-RateLimit-Remaining" => "99" }))
    data = client(t).query("query { me { id } }", { "a" => 1 })
    assert_equal({ "me" => { "id" => "x" } }, data)
    h = calls.first[:headers]
    assert_equal "application/json", h["Content-Type"]
    assert_match %r{\Arailway-pat-cli/}, h["User-Agent"]
    assert_equal "Bearer tok-placeholder", h["Authorization"]
    assert_equal({ "query" => "query { me { id } }", "variables" => { "a" => 1 } }, calls.first[:body])
  end

  def test_records_rate_limit
    t, = fake_transport(resp(200, { data: {} }, { "X-RateLimit-Remaining" => "42", "X-RateLimit-Reset" => "9" }))
    c = client(t)
    c.query("q")
    assert_equal "42", c.rate_limit[:remaining]
    assert_equal "9", c.rate_limit[:reset]
  end

  def test_200_with_errors_raises
    t, = fake_transport(resp(200, { errors: [{ message: "boom", extensions: { code: "X" }, traceId: "tr1" }] }))
    e = assert_raises(RailwayCli::ApiError) { client(t).query("q") }
    assert_equal "boom", e.message
    assert_equal "tr1", e.trace_id
  end

  def test_not_authorized_hint_names_kind_and_source_not_value
    t, = fake_transport(resp(200, { errors: [{ message: "Not Authorized", extensions: { code: "INTERNAL_SERVER_ERROR" } }] }))
    e = assert_raises(RailwayCli::ApiError) { client(t).query("q") }
    assert_includes e.message, "bearer"
    assert_includes e.message, "RAILWAY_PAT_ACCOUNT"
    refute_includes e.message, "tok-placeholder"
  end

  def test_400_raises_first_message
    t, = fake_transport(resp(400, { errors: [{ message: "Cannot query field" }] }))
    e = assert_raises(RailwayCli::ApiError) { client(t).query("q") }
    assert_equal "Cannot query field", e.message
    assert_equal 400, e.status
  end

  def test_query_retries_429_then_succeeds
    t, calls = fake_transport(resp(429, {}, { "Retry-After" => "100" }), resp(200, { data: { ok: 1 } }))
    assert_equal({ "ok" => 1 }, client(t).query("q"))
    assert_equal 2, calls.size
    assert_equal [30], @slept
  end

  def test_query_gives_up_after_two_rate_retries
    t, calls = fake_transport(*Array.new(3) { resp(429, {}, { "Retry-After" => "1" }) })
    assert_raises(RailwayCli::RateLimited) { client(t).query("q") }
    assert_equal 3, calls.size
  end

  def test_mutation_not_retried_on_429
    t, calls = fake_transport(resp(429, {}, { "Retry-After" => "1" }), resp(200, { data: {} }))
    e = assert_raises(RailwayCli::RateLimited) { client(t).mutate("mutation { x }") }
    assert_equal 1, e.retry_after
    assert_equal 1, calls.size
  end

  def test_query_retried_once_on_network_error
    t, calls = fake_transport(-> { raise SocketError, "down" }, resp(200, { data: { ok: 1 } }))
    assert_equal({ "ok" => 1 }, client(t).query("q"))
    assert_equal 2, calls.size
  end

  def test_mutation_not_retried_on_network_error
    t, calls = fake_transport(-> { raise Errno::ECONNRESET }, resp(200, { data: {} }))
    e = assert_raises(RailwayCli::ApiError) { client(t).mutate("mutation { x }") }
    assert_includes e.message, "mutation outcome unknown, check dashboard"
    assert_equal 1, calls.size
  end

  def test_paginate_follows_page_info
    page = lambda do |ids, more, cursor|
      resp(200, { data: { projects: { edges: ids.map { |i| { node: { id: i } } },
                                      pageInfo: { hasNextPage: more, endCursor: cursor } } } })
    end
    t, calls = fake_transport(page.(%w[a b], true, "c1"), page.(%w[c], false, nil))
    nodes = client(t).paginate("q", {}, ["projects"])
    assert_equal %w[a b c], nodes.map { |n| n["id"] }
    assert_equal "c1", calls.last[:body]["variables"]["after"]
  end

  def test_paginate_stops_at_limit
    t, calls = fake_transport(resp(200, { data: { p: { edges: [{ node: 1 }, { node: 2 }],
                                                      pageInfo: { hasNextPage: true, endCursor: "c" } } } }))
    assert_equal [1], client(t).paginate("q", {}, ["p"], limit: 1)
    assert_equal 1, calls.size
  end
end
