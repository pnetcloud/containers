locals {
  ctx = "vendor"
  paths = [format("%s", replace(local.ctx, "vendor", "vendor/src"))]
}

target "image" {
  context = local.paths[0]
}
