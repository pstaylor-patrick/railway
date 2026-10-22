# frozen_string_literal: true

require "railway_cli/commands/context"
require "railway_cli/error"
require "railway_cli/queries"

module RailwayCli
  module Commands
    # domain create --service S [--custom HOST]. domain delete lands with the Confirm helper.
    module Domain
      def self.run(ctx)
        sub = ctx.args.first
        raise UsageError, "unknown domain subcommand: #{sub.inspect} (create)" unless sub == "create"

        create(ctx)
      end

      def self.create(ctx)
        r = ctx.resolver
        base = { "environmentId" => r.environment["id"], "serviceId" => r.service["id"] }
        host = ctx.opts[:custom]
        return service_domain(ctx, base) if host.nil?

        avail = ctx.client.query(Queries::CUSTOM_DOMAIN_AVAILABLE, { "domain" => host })["customDomainAvailable"] || {}
        raise ApiError.new("domain #{host} not available: #{avail['message']}", code: nil, trace_id: nil, status: 200) unless avail["available"]

        d = ctx.client.mutate(Queries::CUSTOM_DOMAIN_CREATE,
                              { "input" => base.merge("projectId" => r.project["id"], "domain" => host) })["customDomainCreate"]
        records = Array(d.dig("status", "dnsRecords"))
        return ctx.emit("domain create", d) if ctx.opts[:json]

        ctx.out.puts "created #{d['domain']}"
        records.each { |rec| ctx.out.puts "  #{rec['recordType']} #{rec['fqdn'] || rec['hostlabel']} -> #{rec['requiredValue']}" }
        0
      end

      def self.service_domain(ctx, base)
        d = ctx.client.mutate(Queries::SERVICE_DOMAIN_CREATE, { "input" => base })["serviceDomainCreate"]
        ctx.emit("domain create", d)
      end
    end
  end
end
