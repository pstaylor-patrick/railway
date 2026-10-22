# frozen_string_literal: true

require "railway_cli/commands/context"

module RailwayCli
  module Commands
    # Volumes per environment with their backups.
    module Volumes
      def self.run(ctx)
        r = ctx.resolver
        p = r.project
        envs = r.environments.to_h { |e| [e["id"], e["name"]] }
        svcs = r.services.to_h { |s| [s["id"], s["name"]] }
        vols = Resolver.nodes(ctx.client.query(Queries::VOLUMES, { "id" => p["id"] }).dig("project", "volumes"))
        rows = vols.flat_map do |v|
          Resolver.nodes(v["volumeInstances"]).map do |i|
            backups = backups(ctx.client, i["id"])
            { "volume" => v["name"], "env" => envs[i["environmentId"]] || i["environmentId"],
              "service" => svcs[i["serviceId"]] || "-", "mount" => i["mountPath"],
              "usedMB" => i["currentSizeMB"]&.round, "sizeMB" => i["sizeMB"], "backups" => backups.size,
              "backup_list" => backups }
          end
        end
        ctx.emit("volumes", rows, rows: rows, cols: %w[volume env service mount usedMB sizeMB backups])
      end

      def self.backups(client, instance_id)
        Array(client.query(Queries::VOLUME_BACKUPS, { "volumeInstanceId" => instance_id })["volumeInstanceBackupList"])
      rescue ApiError
        []
      end
    end
  end
end
