target "image" {
  contexts = {
    source = replace(format("%s", "vendor"), "vendor", "vendor/src")
  }
}
