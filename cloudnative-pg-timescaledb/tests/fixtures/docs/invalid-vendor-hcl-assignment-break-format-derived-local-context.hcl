locals {
  ctx = "vendor"
  out =
    format("%s", format("%s/src", local.ctx))
}

target "image" {
  context = local.out
}
