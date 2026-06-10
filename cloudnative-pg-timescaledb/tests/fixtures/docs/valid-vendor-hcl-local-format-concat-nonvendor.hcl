locals {
  ctx = format("%s-cache", "vendor")
}

target "image" {
  context = local.ctx
}
