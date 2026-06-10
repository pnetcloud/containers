locals {
  ctx = "${path.module}/vendor"
}

target "image" {
  contexts = {
    deps = local.ctx
  }
}
