# frozen_string_literal: true

module RailwayCli
  # Replaces every known token value in text with [REDACTED].
  module Redact
    @tokens = []

    class << self
      def register(token)
        @tokens |= [token] if token && !token.empty?
      end

      def tokens = @tokens.dup

      def reset! = @tokens = []

      def call(text, tokens = @tokens)
        tokens.reduce(text.to_s) { |out, t| t.to_s.empty? ? out : out.gsub(t, "[REDACTED]") }
      end
    end
  end

  class Error < StandardError
    def message = Redact.call(super)
    def code = nil
    def trace_id = nil
  end

  class AuthError < Error; end
  class UsageError < Error; end
  class ConfirmRefused < Error; end

  class ApiError < Error
    attr_reader :code, :trace_id, :status

    def initialize(msg = nil, code: nil, trace_id: nil, status: nil)
      super(msg)
      @code = code
      @trace_id = trace_id
      @status = status
    end
  end

  class RateLimited < ApiError
    attr_reader :retry_after

    def initialize(msg = "rate limited", retry_after: nil, **kw)
      super(msg, code: "RATE_LIMITED", status: 429, **kw)
      @retry_after = retry_after
    end
  end
end
