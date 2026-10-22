# frozen_string_literal: true

require "railway_cli/commands/context"

module RailwayCli
  module Commands
    # Cheap probe, then the last rate-limit headers the API returned.
    module Rate
      def self.run(ctx)
        c = ctx.client
        probe(c)
        data = { "limit" => c.rate_limit[:limit], "remaining" => c.rate_limit[:remaining],
                 "reset" => c.rate_limit[:reset] }.transform_values { |v| v || "unknown" }
        ctx.emit("rate", data)
      end

      # Workspace tokens cannot read `me`, so fall through to apiToken.
      def self.probe(client)
        return client.query(Queries::PROJECT_TOKEN) if client.credential.kind == :project

        client.query(Queries::ME)
      rescue ApiError => e
        raise if e.is_a?(RateLimited)

        client.query(Queries::API_TOKEN)
      end
    end
  end
end
