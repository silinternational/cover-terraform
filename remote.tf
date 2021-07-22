data "terraform_remote_state" "common" {
  backend = "atlas"

  config = {
    name = var.tf_remote_common
  }
}

