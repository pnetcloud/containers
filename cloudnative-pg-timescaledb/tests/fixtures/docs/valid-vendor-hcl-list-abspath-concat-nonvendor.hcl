locals {
  paths = ["context", abspath("./vendor-cache")]
}

target "image" {
  context = local.paths[1]
}
