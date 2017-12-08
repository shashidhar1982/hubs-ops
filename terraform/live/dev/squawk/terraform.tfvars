terragrunt = {
  terraform {
    source = "git::git@github.com:mozilla/mr-ops.git//terraform/modules/squawk"
  }

  include {
    path = "${find_in_parent_folders()}"
  }

  dependencies {
    paths = ["../vpc", "../base", "../bastion", "../hab", "../ret-db", "../ret"]
  }
}

squawk_instance_type = "c4.xlarge"
min_squawk_servers = 1
max_squawk_servers = 1
