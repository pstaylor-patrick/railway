# frozen_string_literal: true

module RailwayCli
  module Queries
    ME = <<~GQL
      query Me { me { id name email } }
    GQL

    API_TOKEN = <<~GQL
      query ApiToken { apiToken { workspaces { id name } } }
    GQL

    PROJECT_TOKEN = <<~GQL
      query ProjectToken { projectToken { projectId environmentId } }
    GQL

    PROJECTS = <<~GQL
      query Projects($first: Int, $after: String) {
        projects(first: $first, after: $after) {
          edges { node { id name workspace { id name } } }
          pageInfo { hasNextPage endCursor }
        }
      }
    GQL

    PROJECT = <<~GQL
      query Project($id: String!) {
        project(id: $id) {
          id name
          environments { edges { node { id name } } }
          services { edges { node { id name } } }
        }
      }
    GQL
  end
end
