# frozen_string_literal: true

module RailwayCli
  # Loads KEY=VALUE lines into env without overriding already-exported keys.
  # Never logs values.
  module Env
    def self.load(path, env = ENV)
      return env unless path && File.file?(path)

      File.foreach(path) do |line|
        line = line.strip
        next if line.empty? || line.start_with?("#")

        line = line.delete_prefix("export ").lstrip
        key, value = line.split("=", 2)
        next unless value && key.match?(/\A[A-Za-z_][A-Za-z0-9_]*\z/)

        env[key] ||= unquote(value.strip)
      end
      env
    end

    def self.unquote(value)
      if value.length >= 2 && %w[" '].include?(value[0]) && value[-1] == value[0]
        value[1..-2]
      else
        value
      end
    end
  end
end
