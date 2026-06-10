locals {
  paths = {
    vendor = {
      nested = {
        ctx = "${path.module}/vendor"
      }
    }
  }
}

target "image" {
  context = local.paths.vendor.nested.ctx
}
