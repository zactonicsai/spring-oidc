output "name" { value = local.name }
output "version" { value = local.version }
output "namespace" { value = local.ns }
output "registry" { value = local.registry }
output "labels" { value = { for k, v in try(local.raw.metadata.labels, {}) : k => tostring(v) } }
output "owner" { value = try(local.raw.metadata.owner, "") }
output "services" { value = local.services_by_name }
output "service_names" { value = [for s in local.services : s.name] }
output "public_service_names" { value = [for s in local.services : s.name if s.is_public] }
output "files" { value = local.files }
output "hosts" { value = local.hosts }
output "azure" { value = local.azure }
output "local_cluster_name" { value = coalesce(try(local.raw.targets.local.clusterName, ""), local.name) }
output "helm_values" { value = local.helm_values }
output "host_config_env" { value = local.host_config_env }
output "host_files_tsv" { value = local.host_files_tsv }
output "host_service_envs" { value = local.host_service_envs }
