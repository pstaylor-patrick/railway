# frozen_string_literal: true

require "railway_cli/commands/context"
require "railway_cli/error"
require "railway_cli/queries"
require "railway_cli/resolver"
require "railway_cli/dashboard"

module RailwayCli
  module Commands
    # env create NAME --project P [--from E]. env delete lands with the Confirm helper.
    module Environment
      def self.run(ctx)
        sub, name = ctx.args
        raise UsageError, "unknown env subcommand: #{sub.inspect} (create)" unless sub == "create"
        raise UsageError, "env create needs NAME" if name.nil? || name.empty?

        r = ctx.resolver
        input = { "projectId" => r.project["id"], "name" => name }
        input["sourceEnvironmentId"] = Resolver.pick(r.environments, ctx.opts[:from], "from")["id"] if ctx.opts[:from]
        env = ctx.client.mutate(Queries::ENVIRONMENT_CREATE, { "input" => input })["environmentCreate"]
        ctx.opts[:dashboard_url] = Dashboard.url(r.project["id"], env["id"])
        ctx.emit("env create", env)
      end
    end
  end
end
