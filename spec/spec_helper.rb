# frozen_string_literal: true

require "minitest/autorun"
require "json"
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

module FakeHttp
  WORKSPACES_PAGE = { data: { me: { workspaces: [{ id: "ws_example" }] } } }.freeze

  # Builds a transport returning queued responses; records requests.
  def fake_transport(*responses)
    calls = []
    t = lambda do |_uri, body, headers|
      calls << { body: JSON.parse(body), headers: headers }
      r = responses.shift or raise "no more fake responses"
      r = r.call if r.respond_to?(:call)
      r
    end
    [t, calls]
  end

  def resp(status = 200, body = {}, headers = {})
    RailwayCli::Client::Response.new(status: status, headers: headers, body: JSON.generate(body))
  end
end
