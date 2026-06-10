locals {
  ctx = abspath(format("%s-cache", "vendor"))
}

target "image" {
  context = local.ctx
}
