# frozen_string_literal: true

require "railway_cli/error"
require "railway_cli/queries"

module RailwayCli
  # Resolves --project/--env/--service by ID, exact name, then case-insensitive name.
  class Resolver
    def self.pick(items, query, kind)
      raise UsageError, "--#{kind} is required" if query.nil? || query.to_s.empty?

      by_id = items.find { |i| i["id"] == query }
      return by_id if by_id

      [->(n) { n == query }, ->(n) { n.to_s.casecmp?(query) }].each do |match|
        hits = items.select { |i| match.call(i["name"]) }
        return hits.first if hits.size == 1
        if hits.size > 1
          raise UsageError, "#{kind} #{query.inspect} is ambiguous; use an ID: " +
                            hits.map { |h| "#{h['name']} (#{h['id']})" }.join(", ")
        end
      end
      names = items.map { |i| i["name"] }.join(", ")
      raise UsageError, "no #{kind} matches #{query.inspect}#{names.empty? ? '' : "; candidates: #{names}"}"
    end

    def self.nodes(conn) = Array(conn && conn["edges"]).map { |e| e["node"] }

    def initialize(client, opts)
      @client = client
      @opts = opts
    end

    def project_token? = @client.credential.kind == :project

    def token_scope
      @token_scope ||= @client.query(Queries::PROJECT_TOKEN)["projectToken"] || {}
    end

    def project
      @project ||= begin
        id = if project_token? && @opts[:project].nil?
               token_scope["projectId"]
             else
               self.class.pick(projects, @opts[:project], "project")["id"]
             end
        @client.query(Queries::PROJECT, { "id" => id })["project"] or raise UsageError, "project not found"
      end
    end

    def projects
      return [@client.query(Queries::PROJECT, { "id" => token_scope["projectId"] })["project"]].compact if project_token?

      @client.paginate(Queries::PROJECTS, { "first" => 50 }, ["projects"])
    end

    def environments = self.class.nodes(project["environments"])
    def services = self.class.nodes(project["services"])

    def environment(required: true)
      if @opts[:env].nil?
        if project_token?
          return environments.find { |e| e["id"] == token_scope["environmentId"] } ||
                 { "id" => token_scope["environmentId"], "name" => token_scope["environmentId"] }
        end
        return nil unless required
      end
      self.class.pick(environments, @opts[:env], "env")
    end

    def service(required: true)
      return nil if @opts[:service].nil? && !required

      self.class.pick(services, @opts[:service], "service")
    end

    # The service instance of svc in env, or nil.
    def instance(svc, env)
      self.class.nodes(svc["serviceInstances"]).find { |i| i["environmentId"] == env["id"] }
    end
  end
end
