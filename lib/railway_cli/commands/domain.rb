# frozen_string_literal: true

require "railway_cli/commands/context"
require "railway_cli/error"
require "railway_cli/confirm"
require "railway_cli/commands/domains"
require "railway_cli/queries"

module RailwayCli
  module Commands
    # domain create --service S [--custom HOST]; domain delete HOST.
    module Domain
      def self.run(ctx)
        sub = ctx.args.first
        case sub
        when "create" then create(ctx)
        when "delete" then delete(ctx, ctx.args[1])
        else raise UsageError, "unknown domain subcommand: #{sub.inspect} (create, delete)"
        end
      end

      # Finds HOST among the environment's service and custom domains, then confirms.
      def self.delete(ctx, host)
        raise UsageError, "domain delete needs HOST" if host.nil? || host.empty?

        r = ctx.resolver
        env = r.environment
        only = r.service(required: false)
        found = find(only ? [only] : r.services, env, r, host)
        raise UsageError, "no domain #{host} in #{env['name']}" unless found

        Confirm.require!(expected: host, kind: "domain", flag: ctx.opts[:confirm])
        doc = found[:kind] == "custom" ? Queries::CUSTOM_DOMAIN_DELETE : Queries::SERVICE_DOMAIN_DELETE
        ctx.client.mutate(doc, { "id" => found[:id] })
        ctx.emit("domain delete", { "deleted" => host })
      end

      def self.find(svcs, env, resolver, host)
        svcs.each do |s|
          d = resolver.instance(s, env)&.dig("domains") || {}
          { "custom" => d["customDomains"], "service" => d["serviceDomains"] }.each do |kind, list|
            hit = Array(list).find { |x| x["domain"] == host }
            return { kind: kind, id: hit["id"] } if hit
          end
        end
        nil
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
