locals {
  ctx = "vendor"
}

target "image" {
  context = format("%s", format("%s/src", local.ctx))
}
