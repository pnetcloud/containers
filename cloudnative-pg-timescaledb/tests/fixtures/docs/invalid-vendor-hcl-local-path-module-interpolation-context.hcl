locals {
  ctx = "vendor"
}

target "image" {
  context = "${path.module}/${local.ctx}"
}
