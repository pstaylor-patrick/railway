# frozen_string_literal: true

require "railway_cli/commands/context"

module RailwayCli
  module Commands
    # Service and custom domains for each service instance in an environment.
    module Domains
      def self.names(inst) = rows_for(inst).map { |d| d["domain"] }

      def self.rows_for(inst)
        d = inst && inst["domains"] || {}
        Array(d["customDomains"]).map { |x| { "domain" => x["domain"], "kind" => "custom" } } +
          Array(d["serviceDomains"]).map { |x| { "domain" => x["domain"], "kind" => "service" } }
      end

      def self.run(ctx)
        r = ctx.resolver
        env = r.environment
        only = r.service(required: false)
        svcs = only ? [only] : r.services
        rows = svcs.flat_map { |s| rows_for(r.instance(s, env)).map { |d| { "service" => s["name"] }.merge(d) } }
        ctx.emit("domains", rows, rows: rows, cols: %w[service domain kind])
      end
    end
  end
end
