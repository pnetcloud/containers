locals {
  paths = [
    abspath("${path.module}/vendor") /* reference, tree */
  ]
}

target "image" {
  context = local.paths[0]
}
