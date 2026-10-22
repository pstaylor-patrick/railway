# frozen_string_literal: true

require "railway_cli/commands/context"
require "railway_cli/commands/domains"

module RailwayCli
  module Commands
    # One line per service in an environment: latest deployment status, time, domain.
    module Status
      def self.rows(resolver, env)
        resolver.services.filter_map do |s|
          inst = resolver.instance(s, env) or next
          dep = inst["latestDeployment"] || {}
          { "service" => s["name"], "status" => dep["status"] || "-",
            "created" => dep["createdAt"] || "-", "domain" => Domains.names(inst).first || "-" }
        end
      end

      def self.run(ctx)
        env = ctx.resolver.environment(required: false) || default_env(ctx.resolver)
        rows = rows(ctx.resolver, env)
        ctx.out.puts "environment: #{env['name']}" unless ctx.opts[:json]
        ctx.emit("status", { "environment" => env, "services" => rows }, rows: rows,
                                                                         cols: %w[service status created domain])
      end

      def self.default_env(resolver)
        envs = resolver.environments
        envs.find { |e| e["name"] == "production" } || envs.first or raise UsageError, "project has no environments"
      end
    end
  end
end
