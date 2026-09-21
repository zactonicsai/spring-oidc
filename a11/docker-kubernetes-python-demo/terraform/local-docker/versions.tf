terraform {
  required_version = ">= 1.10"
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

provider "docker" {
  host = var.docker_host # unix:///var/run/docker.sock (Linux/macOS) or npipe:////./pipe/docker_engine (Windows)
}
