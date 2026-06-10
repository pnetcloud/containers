locals {
  paths = ["vendor"]
}

target "image" {
  context = local.paths[0]
}
