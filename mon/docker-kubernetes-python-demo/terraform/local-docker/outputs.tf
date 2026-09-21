output "urls" {
  description = "Public services on your laptop"
  value = { for n, s in module.app.services : n => [
    for p in s.ports : "http://localhost:${p.service_port}" if p.expose == "public"
  ] if s.is_public }
}

output "containers" {
  value = { for n, c in docker_container.svc : n => { name = c.name, image = module.app.services[n].image } }
}

output "base_host" {
  value = var.create_base_host ? "docker exec -it ${docker_container.base_host[0].name} bash   # then: cat /etc/${local.name}/config.env" : "disabled"
}

output "next_steps" {
  value = <<-EOT
    curl http://localhost:80/            # web (calls api over the docker network)
    curl http://localhost:80/api-config  # web -> api, secret masked
    docker ps --filter network=${local.name}
  EOT
}
