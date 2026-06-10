locals {
  paths = {
    nested = {
      ctx = "${path.module}/vendor"
    }
  }
}

target "image" {
  context = local.paths["nested"].ctx
}
