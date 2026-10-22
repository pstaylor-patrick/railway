# frozen_string_literal: true

require "railway_cli/commands/context"

module RailwayCli
  module Commands
    # Services in a project, optionally only those with an instance in --env.
    module Services
      def self.run(ctx)
        r = ctx.resolver
        env = r.environment(required: false)
        svcs = r.services
        svcs = svcs.select { |s| r.instance(s, env) } if env
        rows = svcs.map { |s| { "name" => s["name"], "id" => s["id"] } }
        ctx.emit("services", rows, rows: rows, cols: %w[name id])
      end
    end
  end
end
