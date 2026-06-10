variable "ctx" {
  default = "vendor"
}

target "image" {
  context = join("/", [ctx, "examples"])
}
