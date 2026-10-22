# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
require "railway_cli/version"
require "railway_cli/error"

module RailwayCli
  class Client
    ENDPOINT = URI("https://backboard.railway.com/graphql/v2")
    NETWORK_ERRORS = [SocketError, Timeout::Error, IOError, SystemCallError, OpenSSL::SSL::SSLError,
                      Net::HTTPBadResponse].freeze
    MAX_RATE_RETRIES = 2
    RETRY_CAP = 30

    # Response shape every transport returns.
    Response = Data.define(:status, :headers, :body)

    DEFAULT_TRANSPORT = lambda do |uri, body, headers|
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 10
      http.read_timeout = 60
      req = Net::HTTP::Post.new(uri)
      headers.each { |k, v| req[k] = v }
      req.body = body
      res = http.request(req)
      Response.new(status: res.code.to_i, headers: res.each_header.to_h, body: res.body.to_s)
    end

    attr_reader :credential, :rate_limit

    def initialize(credential:, transport: DEFAULT_TRANSPORT, sleeper: ->(s) { sleep(s) })
      @credential = credential
      @transport = transport
      @sleeper = sleeper
      @rate_limit = {}
    end

    def query(doc, vars = {})
      rate_retries = 0
      net_retries = 0
      begin
        request(doc, vars)
      rescue RateLimited => e
        raise if rate_retries >= MAX_RATE_RETRIES

        rate_retries += 1
        @sleeper.call([[e.retry_after.to_i, 1].max, RETRY_CAP].min)
        retry
      rescue *NETWORK_ERRORS
        raise ApiError.new("network error", code: "NETWORK") if net_retries >= 1

        net_retries += 1
        retry
      end
    end

    def mutate(doc, vars = {})
      request(doc, vars)
    rescue *NETWORK_ERRORS
      raise ApiError.new("network error: mutation outcome unknown, check dashboard", code: "NETWORK")
    end

    # Follows Relay pageInfo at path (array of keys to the connection) and
    # returns the collected nodes.
    def paginate(doc, vars, path, limit: nil)
      nodes = []
      after = nil
      loop do
        data = query(doc, vars.merge(after ? { "after" => after } : {}))
        conn = data.dig(*path) or break
        nodes.concat(Array(conn["edges"]).map { |e| e["node"] })
        return nodes.first(limit) if limit && nodes.size >= limit

        info = conn["pageInfo"] || {}
        break unless info["hasNextPage"] && info["endCursor"]

        after = info["endCursor"]
      end
      nodes
    end

    private

    def request(doc, vars)
      headers = {
        "Content-Type" => "application/json",
        "User-Agent" => "railway-pat-cli/#{VERSION}"
      }.merge(credential.headers)
      res = @transport.call(ENDPOINT, JSON.generate(query: doc, variables: vars), headers)
      hdrs = res.headers.transform_keys(&:downcase)
      record_rate_limit(hdrs)
      handle(res.status, hdrs, parse(res.body))
    end

    def record_rate_limit(hdrs)
      %w[limit remaining reset].each do |k|
        v = hdrs["x-ratelimit-#{k}"]
        @rate_limit[k.to_sym] = Array(v).first if v
      end
    end

    def parse(body)
      JSON.parse(body.to_s)
    rescue JSON::ParserError
      {}
    end

    def handle(status, hdrs, json)
      if status == 429
        raise RateLimited.new("rate limited (429)", retry_after: Array(hdrs["retry-after"]).first.to_i)
      end

      errors = json.is_a?(Hash) ? Array(json["errors"]) : []
      raise api_error(errors.first, status) if errors.any?
      raise ApiError.new("HTTP #{status}", status: status) unless status == 200

      json["data"] || {}
    end

    def api_error(err, status)
      msg = err["message"].to_s
      ext = err["extensions"] || {}
      code = ext["code"]
      trace = err["traceId"] || ext["traceId"]
      if msg == "Not Authorized"
        msg = "Not Authorized (credential: #{credential.kind} from #{credential.source}); " \
              "try --project-token or the account token"
        code = "NOT_AUTHORIZED"
      end
      ApiError.new(msg, code: code, trace_id: trace, status: status)
    end
  end
end
