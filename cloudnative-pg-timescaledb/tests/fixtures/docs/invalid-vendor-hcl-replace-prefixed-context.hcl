locals {
  ctx = "vendor"
}

target "image" {
  context = replace("prefix/V", "V", local.ctx)
}
