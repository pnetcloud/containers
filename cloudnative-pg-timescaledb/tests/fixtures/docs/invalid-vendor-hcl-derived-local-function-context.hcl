locals {
  base = abspath("${path.module}/vendor")
  ctx = format("%s", local.base)
}

target "image" {
  context = local.ctx
}
