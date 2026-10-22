# frozen_string_literal: true

require "json"
require "railway_cli/gql_guard"
require "railway_cli/formatter"

module RailwayCli
  module Commands
    # Raw GraphQL passthrough: railway gql [-f FILE | QUERY] [--vars JSON] [--write] [--confirm NAME].
    module Gql
      def self.run(ctx)
        doc = document(ctx)
        vars = variables(ctx.opts[:vars])
        ops = GqlGuard.check!(doc, write: ctx.opts[:write], confirm: ctx.opts[:confirm])
        mutation = ops.any? { |o| o.type == "mutation" }
        data = mutation ? ctx.client.mutate(doc, vars) : ctx.client.query(doc, vars)
        ctx.out.puts(ctx.opts[:json] ? Formatter.envelope("gql", data) : JSON.pretty_generate(data))
        0
      end

      def self.document(ctx)
        # -f is shared with logs --follow, so for gql it means "the first argument is a file".
        file = ctx.opts[:file] || (ctx.opts[:follow] ? ctx.args.first : nil)
        doc = file ? File.read(file) : ctx.args.join(" ")
        raise UsageError, "usage: railway gql [-f FILE | QUERY] [--vars JSON] [--write] [--confirm NAME]" if doc.strip.empty?

        doc
      rescue Errno::ENOENT
        raise UsageError, "no such file: #{file}"
      end

      def self.variables(raw)
        return {} unless raw

        v = JSON.parse(raw)
        raise UsageError, "--vars must be a JSON object" unless v.is_a?(Hash)

        v
      rescue JSON::ParserError
        raise UsageError, "--vars is not valid JSON"
      end
    end
  end
end
