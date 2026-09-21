terraform {
  required_version = ">= 1.10"
  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.11"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.1"
    }
  }
}

provider "kind" {}

provider "docker" {
  host = var.docker_host
}

# helm provider v3: `kubernetes` is a nested attribute (= { ... }), not a block
provider "helm" {
  kubernetes = {
    host                   = kind_cluster.this.endpoint
    client_certificate     = kind_cluster.this.client_certificate
    client_key             = kind_cluster.this.client_key
    cluster_ca_certificate = kind_cluster.this.cluster_ca_certificate
  }
}
