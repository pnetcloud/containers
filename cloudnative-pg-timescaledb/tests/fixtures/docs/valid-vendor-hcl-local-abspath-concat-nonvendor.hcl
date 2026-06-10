locals {
  ctx = abspath("./vendor-cache")
}

target "image" {
  context = local.ctx
}
