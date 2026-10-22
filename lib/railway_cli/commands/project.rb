# frozen_string_literal: true

require "railway_cli/commands/context"

module RailwayCli
  module Commands
    # One project: environments and services with each instance's last deployment status.
    module Project
      def self.run(ctx)
        r = ctx.resolver
        p = r.project
        envs = r.environments
        services = r.services.map do |s|
          statuses = Resolver.nodes(s["serviceInstances"]).to_h do |i|
            env = envs.find { |e| e["id"] == i["environmentId"] }
            [env ? env["name"] : i["environmentId"], i.dig("latestDeployment", "status")]
          end
          { "name" => s["name"], "id" => s["id"], "deployments" => statuses }
        end
        data = { "id" => p["id"], "name" => p["name"], "environments" => envs, "services" => services }
        return ctx.emit("project", data) if ctx.opts[:json]

        ctx.out.puts Formatter.kv("project" => "#{p['name']} (#{p['id']})",
                                  "environments" => envs.map { |e| e["name"] }.join(", "))
        rows = services.map do |s|
          { "service" => s["name"], "id" => s["id"],
            "status" => s["deployments"].map { |e, st| "#{e}=#{st || '-'}" }.join(" ") }
        end
        ctx.out.puts
        ctx.emit("project", data, rows: rows, cols: %w[service id status])
      end
    end
  end
end
