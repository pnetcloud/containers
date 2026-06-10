locals {
  ctx = "vendor"
}

target "image" {
  context = format("%s-cache", local.ctx)
}
