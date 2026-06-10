locals {
  ctx = "vendor"
}

target "image" {
  context = "${path.module}/prefix/${local.ctx}"
}
