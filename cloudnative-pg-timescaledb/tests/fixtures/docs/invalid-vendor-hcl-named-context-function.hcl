target "image" {
  contexts = {
    deps = abspath("${path.module}/vendor")
  }
}
