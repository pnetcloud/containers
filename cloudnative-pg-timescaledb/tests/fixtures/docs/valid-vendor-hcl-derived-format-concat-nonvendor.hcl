locals {
  base = "vendor"
  ctx  = format("%s-cache", local.base)
}

target "image" {
  context = local.ctx
}
