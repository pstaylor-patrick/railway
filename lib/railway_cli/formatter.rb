# frozen_string_literal: true

require "json"

module RailwayCli
  module Formatter
    module_function

    def table(rows, cols)
      cells = rows.map { |r| cols.map { |c| (r[c] || r[c.to_s]).to_s } }
      header = cols.map { |c| c.to_s.upcase }
      widths = header.each_index.map { |i| ([header[i]] + cells.map { |r| r[i] }).map(&:length).max }
      ([header] + cells).map { |r| r.each_with_index.map { |v, i| v.ljust(widths[i]) }.join("  ").rstrip }.join("\n")
    end

    def kv(hash)
      width = hash.keys.map { |k| k.to_s.length }.max || 0
      hash.map { |k, v| "#{k.to_s.ljust(width)}  #{v}" }.join("\n")
    end

    def envelope(command, data)
      JSON.generate(ok: true, command: command, data: data)
    end

    def error_envelope(err)
      JSON.generate(ok: false, error: {
                      message: err.message,
                      code: err.respond_to?(:code) ? err.code : nil,
                      traceId: err.respond_to?(:trace_id) ? err.trace_id : nil
                    })
    end
  end
end
