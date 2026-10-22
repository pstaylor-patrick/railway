# frozen_string_literal: true

require "railway_cli/commands/context"
require "railway_cli/error"
require "railway_cli/confirm"
require "railway_cli/queries"
require "railway_cli/resolver"
require "railway_cli/dashboard"

module RailwayCli
  module Commands
    # project create NAME [--workspace W]; project delete NAME.
    module ProjectWrite
      def self.run(ctx)
        sub, name = ctx.args
        raise UsageError, "unknown project subcommand: #{sub.inspect} (create, delete)" unless %w[create delete].include?(sub)
        raise UsageError, "project #{sub} needs NAME" if name.nil? || name.empty?
        raise UsageError, "project #{sub} needs an account or workspace token" if ctx.resolver.project_token?
        return delete(ctx, name) if sub == "delete"

        input = { "name" => name }
        input["workspaceId"] = workspace_id(ctx, ctx.opts[:workspace]) if ctx.opts[:workspace]
        proj = ctx.client.mutate(Queries::PROJECT_CREATE, { "input" => input })["projectCreate"]
        ctx.opts[:dashboard_url] = Dashboard.url(proj["id"])
        ctx.emit("project create", proj)
      end

      def self.delete(ctx, name)
        proj = Resolver.pick(ctx.resolver.projects, name, "project")
        Confirm.require!(expected: proj["name"], kind: "project", flag: ctx.opts[:confirm])
        ctx.client.mutate(Queries::PROJECT_DELETE, { "id" => proj["id"] })
        ctx.opts[:dashboard_url] = nil # the project is gone; there is no page to link
        ctx.emit("project delete", { "deleted" => proj["name"] })
      end

      # Workspace by name from visible projects; an unknown value is passed through as an ID.
      def self.workspace_id(ctx, query)
        known = ctx.resolver.projects.filter_map { |p| p["workspace"] }.uniq { |w| w["id"] }
        Resolver.pick(known, query, "workspace")["id"]
      rescue UsageError => e
        raise if e.message.include?("ambiguous")

        query
      end
    end
  end
end
