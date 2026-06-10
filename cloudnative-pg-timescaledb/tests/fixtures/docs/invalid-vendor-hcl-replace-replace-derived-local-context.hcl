locals {
  ctx = "vendor"
  out = replace(replace(local.ctx, "vendor", "vendor/src"), "src", "src")
}

target "image" {
  context = local.out
}
