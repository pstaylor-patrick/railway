# frozen_string_literal: true

require "railway_cli/error"

module RailwayCli
  Credential = Data.define(:kind, :token, :source) do
    def headers = kind == :project ? { "Project-Access-Token" => token } : { "Authorization" => "Bearer #{token}" }
    def inspect = "#<Credential #{kind} from #{source}>"
    alias to_s inspect
  end

  module Auth
    BEARER_KEYS  = %w[RAILWAY_PAT_ACCOUNT RAILWAY_API_TOKEN].freeze
    PROJECT_KEYS = %w[RAILWAY_PAT_PROJECT RAILWAY_TOKEN].freeze

    def self.pick(env, project_token: false)
      bearer  = first(env, BEARER_KEYS)
      project = first(env, PROJECT_KEYS)
      return Credential.new(:project, *project) if project && (project_token || bearer.nil?)
      return Credential.new(:bearer, *bearer) if bearer
      raise AuthError, "no token: set RAILWAY_PAT_ACCOUNT or RAILWAY_PAT_PROJECT"
    end

    def self.first(env, keys)
      key = keys.find { |k| env[k] && !env[k].strip.empty? }
      key && [env[key].strip, key]
    end

    # Each available credential, bearer then project, for commands like whoami.
    def self.all(env)
      { bearer: BEARER_KEYS, project: PROJECT_KEYS }.to_h do |kind, keys|
        pair = first(env, keys)
        [kind, pair && Credential.new(kind, *pair)]
      end
    end

    def self.register_tokens(env)
      (BEARER_KEYS + PROJECT_KEYS).each { |k| Redact.register(env[k]&.strip) }
    end
  end
end
