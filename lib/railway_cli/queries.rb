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
          workspace { id name }
          environments { edges { node { id name } } }
          services {
            edges {
              node {
                id name
                serviceInstances {
                  edges {
                    node {
                      environmentId
                      latestDeployment { id status createdAt }
                      domains { serviceDomains { domain } customDomains { domain } }
                    }
                  }
                }
              }
            }
          }
        }
      }
    GQL

    DEPLOYMENTS = <<~GQL
      query Deployments($first: Int, $after: String, $input: DeploymentListInput!) {
        deployments(first: $first, after: $after, input: $input) {
          edges { node { id status createdAt staticUrl meta } }
          pageInfo { hasNextPage endCursor }
        }
      }
    GQL

    VOLUMES = <<~GQL
      query Volumes($id: String!) {
        project(id: $id) {
          volumes {
            edges {
              node {
                id name
                volumeInstances {
                  edges { node { id environmentId mountPath currentSizeMB sizeMB serviceId } }
                }
              }
            }
          }
        }
      }
    GQL

    VOLUME_BACKUPS = <<~GQL
      query VolumeBackups($volumeInstanceId: String!) {
        volumeInstanceBackupList(volumeInstanceId: $volumeInstanceId) { id name createdAt }
      }
    GQL
  end
end
