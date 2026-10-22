# frozen_string_literal: true

require "json"
require "railway_cli/commands/context"
require "railway_cli/log_poller"
require "railway_cli/queries"

module RailwayCli
  module Commands
    # logs --project P --env E --service S [--build] [--deployment ID] [-n 200] [--filter Q] [-f] [--interval 3]
    module Logs
      def self.run(ctx, sleeper: ->(s) { sleep(s) })
        deployment_id = ctx.opts[:deployment] || latest_deployment_id(ctx)
        doc, key = ctx.opts[:build] ? [Queries::BUILD_LOGS, "buildLogs"] : [Queries::DEPLOYMENT_LOGS, "deploymentLogs"]
        limit = ctx.opts[:limit] || 200
        fetch = lambda do |start|
          vars = { "deploymentId" => deployment_id, "limit" => limit }
          vars["filter"] = ctx.opts[:filter] if ctx.opts[:filter]
          vars["startDate"] = start if start
          [Array(ctx.client.query(doc, vars)[key]), ctx.client.rate_limit]
        end
        poller = LogPoller.new(fetch: fetch, sleep: sleeper, interval: ctx.opts[:interval] || 3,
                               max_iterations: ctx.opts[:follow] ? ctx.opts[:max_polls] : 1)
        emit = ->(l) { ctx.out.puts(ctx.opts[:json] ? JSON.generate(l) : format_line(l)) }
        begin
          poller.run(&emit)
        rescue Interrupt
          poller.stop! # Ctrl-C ends -f cleanly
        end
        0
      end

      def self.format_line(l)
        [l["timestamp"], l["severity"], l["message"]].compact.join(" ")
      end

      def self.latest_deployment_id(ctx)
        r = ctx.resolver
        inst = r.instance(r.service, r.environment)
        id = inst && inst.dig("latestDeployment", "id")
        raise UsageError, "no deployment found for that service; pass --deployment ID" unless id

        id
      end
    end
  end
end
