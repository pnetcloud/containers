locals {
  ctx = "vendor"
}

target "image" {
  context = format("%s/%s", path.module, local.ctx)
}
