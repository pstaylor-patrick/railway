# frozen_string_literal: true

require "railway_cli/auth"
require "railway_cli/client"
require "railway_cli/queries"
require "railway_cli/formatter"

module RailwayCli
  module Commands
    # Probes each available credential: me -> apiToken -> projectToken.
    module Whoami
      PROBES = [
        [:account, Queries::ME, ->(d) { d["me"] && { "id" => d["me"]["id"], "name" => d["me"]["name"], "email" => d["me"]["email"] } }],
        [:workspace, Queries::API_TOKEN, ->(d) { d["apiToken"] && { "workspaces" => Array(d["apiToken"]["workspaces"]) } }],
        [:project, Queries::PROJECT_TOKEN, ->(d) { d["projectToken"] }]
      ].freeze

      module_function

      def report(env, transport: Client::DEFAULT_TRANSPORT)
        Auth.all(env).to_h do |kind, cred|
          [kind.to_s, cred ? probe(cred, transport) : { "status" => "not set" }]
        end
      end

      def probe(cred, transport)
        client = Client.new(credential: cred, transport: transport)
        last = nil
        PROBES.each do |type, doc, extract|
          identity = extract.call(client.query(doc))
          return { "source" => cred.source, "type" => type.to_s, "identity" => identity } if identity
        rescue ApiError => e
          last = e
        end
        { "source" => cred.source, "type" => "unknown", "error" => last&.message || "no probe succeeded" }
      end

      def run(env, json:, out: $stdout, transport: Client::DEFAULT_TRANSPORT)
        data = report(env, transport: transport)
        if json
          out.puts Formatter.envelope("whoami", data)
        else
          data.each do |kind, r|
            out.puts "#{kind}: #{r['status'] || "#{r['source']} -> #{r['type']}"}"
            out.puts "  #{summary(r)}" unless r["status"]
          end
        end
        0
      end

      def summary(r)
        return "error: #{r['error']}" if r["error"]

        id = r["identity"]
        case r["type"]
        when "account" then "#{id['name']} <#{id['email']}> (#{id['id']})"
        when "workspace" then "workspaces: " + id["workspaces"].map { |w| w["name"] }.join(", ")
        else "project #{id['projectId']} env #{id['environmentId']}"
        end
      end
    end
  end
end
