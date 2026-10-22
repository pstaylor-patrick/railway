# frozen_string_literal: true

require "railway_cli/commands/context"
require "railway_cli/error"
require "railway_cli/queries"

module RailwayCli
  module Commands
    # redeploy/restart/rollback/stop/cancel on --deployment ID or the service's latest deployment.
    module DeploymentAction
      ACTIONS = Queries::DEPLOYMENT_MUTATIONS.keys.freeze

      def self.for(action)
        raise ArgumentError, action unless ACTIONS.include?(action)

        ->(ctx) { run(ctx, action) }
      end

      def self.run(ctx, action)
        id = ctx.opts[:deployment] || latest_id(ctx)
        data = ctx.client.mutate(Queries::DEPLOYMENT_MUTATIONS.fetch(action), { "id" => id })
        ctx.emit(action, { "deployment" => id, "result" => data.values.first })
      end

      def self.latest_id(ctx)
        r = ctx.resolver
        raise UsageError, "pass --deployment ID or --service" if ctx.opts[:service].nil?

        input = { "projectId" => r.project["id"], "environmentId" => r.environment["id"], "serviceId" => r.service["id"] }
        node = ctx.client.query(Queries::DEPLOYMENTS, { "first" => 1, "input" => input })
                  .dig("deployments", "edges", 0, "node")
        node or raise UsageError, "no deployments for that service"
        node["id"]
      end
    end

    # deploy --service S, or deploy --env E --all (every service in the environment).
    module Deploy
      def self.run(ctx)
        r = ctx.resolver
        env = r.environment
        if ctx.opts[:all]
          ids = r.services.select { |s| r.instance(s, env) }.map { |s| s["id"] }
          ids.each do |sid|
            ctx.client.mutate(Queries::ENVIRONMENT_TRIGGERS_DEPLOY,
                              { "input" => { "projectId" => r.project["id"], "environmentId" => env["id"], "serviceId" => sid } })
          end
          return ctx.emit("deploy", { "environment" => env["id"], "services" => ids })
        end
        raise UsageError, "deploy needs --service S or --all" if ctx.opts[:service].nil?

        svc = r.service
        ctx.client.mutate(Queries::SERVICE_INSTANCE_DEPLOY, { "serviceId" => svc["id"], "environmentId" => env["id"] })
        ctx.emit("deploy", { "environment" => env["id"], "service" => svc["id"] })
      end
    end
  end
end
