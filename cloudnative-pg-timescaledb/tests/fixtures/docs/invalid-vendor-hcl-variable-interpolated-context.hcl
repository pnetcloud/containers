variable "ctx" {
  default = "vendor"
}

target "image" {
  context = "${ctx}/examples"
}
