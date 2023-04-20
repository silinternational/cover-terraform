terraform {
  cloud {
    organization = "gtis"
    workspaces {
      tags = ["app:cover"]
    }
  }
}
