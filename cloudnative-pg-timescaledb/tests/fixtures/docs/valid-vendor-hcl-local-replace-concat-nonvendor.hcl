locals {
  ctx = replace("vendor", "vendor", "vendor-cache")
}

target "image" {
  context = local.ctx
}
