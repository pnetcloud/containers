locals {
  paths = {
    ctx = abspath("${path.module}/vendor")
  }
}

target "image" {
  context = local.paths.ctx
}
