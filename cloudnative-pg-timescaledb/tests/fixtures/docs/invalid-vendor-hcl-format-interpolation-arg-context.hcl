locals {
  ctx = "vendor"
}

target "image" {
  context = format("%s", "${local.ctx}/src")
}
