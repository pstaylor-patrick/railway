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
    DEPLOYMENT_LOGS = <<~GQL
      query DeploymentLogs($deploymentId: String!, $limit: Int, $filter: String, $startDate: DateTime) {
        deploymentLogs(deploymentId: $deploymentId, limit: $limit, filter: $filter, startDate: $startDate) {
          timestamp message severity
        }
      }
    GQL

    BUILD_LOGS = <<~GQL
      query BuildLogs($deploymentId: String!, $limit: Int, $filter: String, $startDate: DateTime) {
        buildLogs(deploymentId: $deploymentId, limit: $limit, filter: $filter, startDate: $startDate) {
          timestamp message severity
        }
      }
    GQL

    VARIABLES = <<~GQL
      query Variables($projectId: String!, $environmentId: String!, $serviceId: String) {
        variables(projectId: $projectId, environmentId: $environmentId, serviceId: $serviceId)
      }
    GQL

    VARIABLE_UPSERT = <<~GQL
      mutation VariableUpsert($input: VariableUpsertInput!) { variableUpsert(input: $input) }
    GQL

    VARIABLE_COLLECTION_UPSERT = <<~GQL
      mutation VariableCollectionUpsert($input: VariableCollectionUpsertInput!) {
        variableCollectionUpsert(input: $input)
      }
    GQL

    DEPLOYMENT_MUTATIONS = {
      "redeploy" => "mutation DeploymentRedeploy($id: String!) { deploymentRedeploy(id: $id) { id status } }",
      "restart" => "mutation DeploymentRestart($id: String!) { deploymentRestart(id: $id) }",
      "rollback" => "mutation DeploymentRollback($id: String!) { deploymentRollback(id: $id) }",
      "stop" => "mutation DeploymentStop($id: String!) { deploymentStop(id: $id) }",
      "cancel" => "mutation DeploymentCancel($id: String!) { deploymentCancel(id: $id) }"
    }.freeze

    SERVICE_INSTANCE_DEPLOY = <<~GQL
      mutation ServiceInstanceDeploy($serviceId: String!, $environmentId: String!) {
        serviceInstanceDeploy(serviceId: $serviceId, environmentId: $environmentId)
      }
    GQL

    ENVIRONMENT_TRIGGERS_DEPLOY = <<~GQL
      mutation EnvironmentTriggersDeploy($input: EnvironmentTriggersDeployInput!) {
        environmentTriggersDeploy(input: $input)
      }
    GQL

    CUSTOM_DOMAIN_AVAILABLE = <<~GQL
      query CustomDomainAvailable($domain: String!) { customDomainAvailable(domain: $domain) { available message } }
    GQL

    SERVICE_DOMAIN_CREATE = <<~GQL
      mutation ServiceDomainCreate($input: ServiceDomainCreateInput!) { serviceDomainCreate(input: $input) { id domain } }
    GQL

    CUSTOM_DOMAIN_CREATE = <<~GQL
      mutation CustomDomainCreate($input: CustomDomainCreateInput!) {
        customDomainCreate(input: $input) {
          id domain
          status { dnsRecords { recordType hostlabel fqdn requiredValue } }
        }
      }
    GQL

    ENVIRONMENT_CREATE = <<~GQL
      mutation EnvironmentCreate($input: EnvironmentCreateInput!) { environmentCreate(input: $input) { id name } }
    GQL

    PROJECT_CREATE = <<~GQL
      mutation ProjectCreate($input: ProjectCreateInput!) { projectCreate(input: $input) { id name } }
    GQL
  end
end
