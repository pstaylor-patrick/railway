# frozen_string_literal: true

require "railway_cli/commands/context"
require "railway_cli/error"
require "railway_cli/confirm"
require "railway_cli/queries"
require "railway_cli/resolver"
require "railway_cli/dashboard"

module RailwayCli
  module Commands
    # env create NAME --project P [--from E]; env delete NAME --project P.
    module Environment
      def self.run(ctx)
        sub, name = ctx.args
        raise UsageError, "unknown env subcommand: #{sub.inspect} (create, delete)" unless %w[create delete].include?(sub)
        raise UsageError, "env #{sub} needs NAME" if name.nil? || name.empty?
        return delete(ctx, name) if sub == "delete"

        r = ctx.resolver
        input = { "projectId" => r.project["id"], "name" => name }
        input["sourceEnvironmentId"] = Resolver.pick(r.environments, ctx.opts[:from], "from")["id"] if ctx.opts[:from]
        env = ctx.client.mutate(Queries::ENVIRONMENT_CREATE, { "input" => input })["environmentCreate"]
        ctx.opts[:dashboard_url] = Dashboard.url(r.project["id"], env["id"])
        ctx.emit("env create", env)
      end

      def self.delete(ctx, name)
        r = ctx.resolver
        env = Resolver.pick(r.environments, name, "env")
        Confirm.require!(expected: env["name"], kind: "environment", flag: ctx.opts[:confirm])
        ctx.client.mutate(Queries::ENVIRONMENT_DELETE, { "id" => env["id"] })
        ctx.opts[:dashboard_url] = Dashboard.url(r.project["id"])
        ctx.emit("env delete", { "deleted" => env["name"] })
      end
    end
  end
end
