locals {
  ctx = "vendor"
  out = format("%s", replace(local.ctx, "vendor", "vendor/src"))
}

target "image" {
  context = local.out
}
