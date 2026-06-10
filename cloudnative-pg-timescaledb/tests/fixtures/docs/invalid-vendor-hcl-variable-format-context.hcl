variable "ctx" {
  default = "vendor"
}

target "image" {
  context = format("%s/examples", ctx)
}
