locals {
  ctx = abspath("${path.module}/vendor")
}

target "image" {
  context = local.ctx
}
