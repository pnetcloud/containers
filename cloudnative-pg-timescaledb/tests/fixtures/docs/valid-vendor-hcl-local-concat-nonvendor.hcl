locals {
  ctx = "vendor"
}

target "image" {
  context = "${local.ctx}-cache"
}
