locals {
  ctx = "vendor"
  paths = [format(
    "%s",
    format("%s/src", local.ctx)
  )]
}

target "image" {
  context = local.paths[0]
}
