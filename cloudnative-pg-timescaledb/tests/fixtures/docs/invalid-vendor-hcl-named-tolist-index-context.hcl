target "image" {
  contexts = {
    src = tolist(["vendor"])[0]
  }
}
