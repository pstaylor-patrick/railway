# frozen_string_literal: true

require "railway_cli/formatter"
require "railway_cli/resolver"

module RailwayCli
  module Commands
    # What a read command needs: an API client, a resolver, flags, and an output stream.
    Context = Data.define(:client, :resolver, :opts, :args, :out) do
      def emit(command, data, rows: nil, cols: nil)
        if opts[:json]
          out.puts Formatter.envelope(command, data)
        elsif rows
          out.puts rows.empty? ? "(none)" : Formatter.table(rows, cols)
        else
          out.puts Formatter.kv(data)
        end
        0
      end
    end
  end
end
