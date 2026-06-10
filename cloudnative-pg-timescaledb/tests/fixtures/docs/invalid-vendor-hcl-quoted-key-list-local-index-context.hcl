locals {
  cfg = {
    "ctx-paths" = [abspath("${path.module}/vendor")]
  }
}

target "image" {
  context = local.cfg["ctx-paths"][0]
}
