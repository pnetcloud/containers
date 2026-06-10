locals {
  paths = [
    "context",
    abspath("${path.module}/vendor"),
  ]
}

target "image" {
  context = local.paths[1]
}
