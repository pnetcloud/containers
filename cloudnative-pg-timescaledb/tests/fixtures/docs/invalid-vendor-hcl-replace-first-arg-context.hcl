locals {
  ctx = "vendor"
}

target "image" {
  context = replace(local.ctx, "vendor", "vendor/src")
}
