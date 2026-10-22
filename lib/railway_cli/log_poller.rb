# frozen_string_literal: true

module RailwayCli
  # Polls a log source, printing each line once. fetch.(start_date) returns
  # [lines, rate_limit]; sleep.(seconds) waits. Both are injected for specs.
  class LogPoller
    MIN_INTERVAL = 2
    BACKOFF_INTERVAL = 30
    BACKOFF_RATIO = 0.10

    def initialize(fetch:, sleep:, interval: 3, max_iterations: nil)
      @fetch = fetch
      @sleep = sleep
      @interval = [interval.to_f, MIN_INTERVAL].max
      @max_iterations = max_iterations
      @last_ts = nil
      @seen_at_boundary = []
      @stopped = false
    end

    attr_reader :interval

    def stop! = @stopped = true
    def stopped? = @stopped

    # Yields each new line. Loops until stop!, or max_iterations polls.
    def run(&emit)
      polls = 0
      until @stopped
        lines, rate = @fetch.call(@last_ts)
        fresh(lines).each(&emit)
        polls += 1
        break if @max_iterations && polls >= @max_iterations
        break if @stopped

        @sleep.call(next_interval(rate))
      end
    end

    # Drops lines already printed at the last-seen timestamp and older ones.
    def fresh(lines)
      out = Array(lines).reject do |l|
        ts = l["timestamp"]
        @last_ts && ts && (ts < @last_ts || (ts == @last_ts && @seen_at_boundary.include?(l["message"])))
      end
      out.each do |l|
        ts = l["timestamp"]
        next unless ts

        if @last_ts.nil? || ts > @last_ts
          @last_ts = ts
          @seen_at_boundary = []
        end
        @seen_at_boundary << l["message"] if ts == @last_ts
      end
      out
    end

    def next_interval(rate)
      self.class.low_rate?(rate) ? [BACKOFF_INTERVAL, @interval].max : @interval
    end

    def self.low_rate?(rate)
      return false unless rate

      limit = rate[:limit].to_f
      remaining = rate[:remaining]
      return false if limit <= 0 || remaining.nil?

      remaining.to_f < limit * BACKOFF_RATIO
    end
  end
end
