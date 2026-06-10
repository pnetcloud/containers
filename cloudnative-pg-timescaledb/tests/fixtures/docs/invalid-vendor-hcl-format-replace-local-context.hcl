locals {
  ctx = "vendor"
}

target "image" {
  context = format("%s", replace(local.ctx, "vendor", "vendor/src"))
}
