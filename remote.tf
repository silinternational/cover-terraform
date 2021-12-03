data "terraform_remote_state" "common" {
  backend = "remote"

  config = {
    organization = var.tf_remote_common_organization
    workspaces = {
      name = var.tf_remote_common_workspace
    }
  }
}

