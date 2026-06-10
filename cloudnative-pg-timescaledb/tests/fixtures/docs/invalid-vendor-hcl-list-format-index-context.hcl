locals {
  paths = [format("%s", "${path.module}/vendor")]
}

target "image" {
  context = local.paths[0]
}
