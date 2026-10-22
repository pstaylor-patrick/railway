# frozen_string_literal: true

require "railway_cli/commands/context"

module RailwayCli
  module Commands
    module Deployments
      def self.run(ctx)
        r = ctx.resolver
        input = { "projectId" => r.project["id"], "environmentId" => r.environment["id"],
                  "serviceId" => r.service["id"] }
        limit = ctx.opts[:limit] || 10
        nodes = ctx.client.paginate(Queries::DEPLOYMENTS, { "first" => [limit, 50].min, "input" => input },
                                    ["deployments"], limit: limit)
        rows = nodes.map do |d|
          { "id" => d["id"], "status" => d["status"], "created" => d["createdAt"], "url" => d["staticUrl"] }
        end
        ctx.emit("deployments", rows, rows: rows, cols: %w[id status created url])
      end
    end
  end
end
