locals {
  base = "vendor"
  ctx  = "${local.base}-cache"
}

target "image" {
  context = local.ctx
}
