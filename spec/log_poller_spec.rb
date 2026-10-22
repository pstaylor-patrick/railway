# frozen_string_literal: true

require_relative "spec_helper"
require "stringio"
require "railway_cli/log_poller"
require "railway_cli/client"
require "railway_cli/auth"
require "railway_cli/commands/logs"

class LogPollerTest < Minitest::Test
  include FakeHttp

  def line(ts, msg) = { "timestamp" => ts, "message" => msg }

  def poller(batches, rate: nil, **kw)
    starts = []
    sleeps = []
    fetch = lambda do |start|
      starts << start
      [batches.shift || [], rate]
    end
    p = RailwayCli::LogPoller.new(fetch: fetch, sleep: ->(s) { sleeps << s }, **kw)
    [p, starts, sleeps]
  end

  def test_dedupes_lines_at_boundary
    p, starts, = poller([[line("t1", "a"), line("t2", "b")],
                         [line("t2", "b"), line("t2", "c"), line("t3", "d")],
                         [line("t3", "d")]], max_iterations: 3)
    got = []
    p.run { |l| got << l["message"] }
    assert_equal %w[a b c d], got
    assert_equal [nil, "t2", "t3"], starts
  end

  def test_stops_after_n_iterations
    p, starts, sleeps = poller([], max_iterations: 4)
    p.run { nil }
    assert_equal 4, starts.size
    assert_equal 3, sleeps.size
  end

  def test_interval_floor_is_two_seconds
    p, = poller([], interval: 0.5)
    assert_equal 2, p.interval
  end

  def test_backs_off_under_ten_percent_remaining
    _, _, sleeps = poller([], rate: { limit: "100", remaining: "9" }, interval: 3, max_iterations: 2).tap { |p, *| p.run { nil } }
    assert_equal [30], sleeps
    _, _, sleeps = poller([], rate: { limit: "100", remaining: "10" }, interval: 3, max_iterations: 2).tap { |p, *| p.run { nil } }
    assert_equal [3.0], sleeps
  end

  def test_stop_ends_loop
    starts = []
    sleeper_poller = RailwayCli::LogPoller.new(fetch: ->(_) { starts << 1; [[], nil] }, sleep: ->(_) { sleeper_poller.stop! })
    sleeper_poller.run { nil }
    assert_equal 1, starts.size
  end

  def test_command_json_one_object_per_line
    cred = RailwayCli::Credential.new(:bearer, "tok-placeholder", "RAILWAY_PAT_ACCOUNT")
    t, calls = fake_transport(resp(200, { data: { deploymentLogs: [{ timestamp: "t1", message: "hi", severity: "info" }] } }))
    client = RailwayCli::Client.new(credential: cred, transport: t)
    out = StringIO.new
    opts = { json: true, deployment: "dep_example", filter: "err" }
    ctx = RailwayCli::Commands::Context.new(client: client, resolver: RailwayCli::Resolver.new(client, opts),
                                            opts: opts, args: [], out: out)
    assert_equal 0, RailwayCli::Commands::Logs.run(ctx)
    assert_equal "hi", JSON.parse(out.string.lines.first)["message"]
    assert_equal({ "deploymentId" => "dep_example", "limit" => 200, "filter" => "err" }, calls.first[:body]["variables"])
  end
end
