locals {
  cfg = {
    paths = [
      "context",
      abspath("${path.module}/vendor"),
    ]
  }
}

target "image" {
  context = local.cfg.paths[1]
}
