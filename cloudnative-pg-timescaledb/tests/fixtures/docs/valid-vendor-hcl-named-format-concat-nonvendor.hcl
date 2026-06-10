locals {
  ctx = "vendor"
}

target "image" {
  contexts = {
    cache = format("%s-cache", local.ctx)
  }
}
