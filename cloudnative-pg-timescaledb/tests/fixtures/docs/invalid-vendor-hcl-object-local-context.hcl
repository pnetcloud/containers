locals {
  paths = {
    ctx = "${path.module}/vendor"
  }
}

target "image" {
  context = local.paths.ctx
}
