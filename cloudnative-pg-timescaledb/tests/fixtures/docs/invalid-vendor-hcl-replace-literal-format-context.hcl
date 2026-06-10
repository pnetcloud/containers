target "image" {
  context = replace(format("%s", "vendor"), "vendor", "vendor/src")
}
