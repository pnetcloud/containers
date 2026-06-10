locals {
  ctx = "vendor"
}

target "image" {
  context = abspath(local.ctx)
}
