locals {
  ctx = "vendor"
}

target "image" {
  context = replace(replace(local.ctx, "vendor", "vendor/src"), "src", "src")
}
