locals {
  ctx = "vendor"
  paths = [replace(
    replace(local.ctx, "vendor", "vendor/src"),
    "src",
    "src"
  )]
}

target "image" {
  context = local.paths[0]
}
