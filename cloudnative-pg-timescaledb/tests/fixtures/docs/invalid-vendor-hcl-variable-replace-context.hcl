variable "ctx" {
  default = "vendor"
}

target "image" {
  context = replace("x", "x", ctx)
}
