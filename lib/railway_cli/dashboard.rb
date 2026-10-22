# frozen_string_literal: true

module RailwayCli
  # Dashboard links printed after writes (the VM is headless, so nothing is opened).
  module Dashboard
    BASE = "https://railway.com/project"

    def self.url(project_id, env_id = nil, service_id = nil)
      path = service_id ? "#{BASE}/#{project_id}/service/#{service_id}" : "#{BASE}/#{project_id}"
      env_id ? "#{path}?environmentId=#{env_id}" : path
    end
  end
end
