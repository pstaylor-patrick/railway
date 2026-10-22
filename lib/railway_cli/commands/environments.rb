# frozen_string_literal: true

require "railway_cli/commands/context"

module RailwayCli
  module Commands
    module Environments
      def self.run(ctx)
        rows = ctx.resolver.environments
        ctx.emit("environments", rows, rows: rows, cols: %w[name id])
      end
    end
  end
end
