locals {
  ctx = "vendor"
}

target "image" {
  context = format("prefix/%s", local.ctx)
}
