locals {
  paths = {
    "ctx-path" = "${path.module}/vendor"
  }
}

target "image" {
  context = local.paths["ctx-path"]
}
