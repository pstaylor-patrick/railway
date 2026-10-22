# frozen_string_literal: true

require "railway_cli/commands/context"

module RailwayCli
  module Commands
    module Projects
      def self.run(ctx)
        rows = ctx.resolver.projects.map do |p|
          { "name" => p["name"], "id" => p["id"], "workspace" => p.dig("workspace", "name") }
        end
        ctx.emit("projects", rows, rows: rows, cols: %w[name id workspace])
      end
    end
  end
end
