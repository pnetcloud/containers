locals {
  ctx = "vendor"
}

target "image" {
  context = replace(format("%s", local.ctx), "vendor", "vendor/src")
}
