variable "shared" { type = "map" }
terraform { backend "s3" {} }
provider "aws" { region = "${var.shared["region"]}", version = "~> 0.1" }
data "aws_availability_zones" "all" {}

data "terraform_remote_state" "vpc" { backend = "s3", config = { key = "vpc/terraform.tfstate", bucket = "${var.shared["state_bucket"]}", region = "${var.shared["region"]}", dynamodb_table = "${var.shared["dynamodb_table"]}", encrypt = "true" } }
data "terraform_remote_state" "base" { backend = "s3", config = { key = "base/terraform.tfstate", bucket = "${var.shared["state_bucket"]}", region = "${var.shared["region"]}", dynamodb_table = "${var.shared["dynamodb_table"]}", encrypt = "true" } }
data "terraform_remote_state" "bastion" { backend = "s3", config = { key = "bastion/terraform.tfstate", bucket = "${var.shared["state_bucket"]}", region = "${var.shared["region"]}", dynamodb_table = "${var.shared["dynamodb_table"]}", encrypt = "true" } }
data "terraform_remote_state" "ret" { backend = "s3", config = { key = "ret/terraform.tfstate", bucket = "${var.shared["state_bucket"]}", region = "${var.shared["region"]}", dynamodb_table = "${var.shared["dynamodb_table"]}", encrypt = "true" } }

data "aws_ami" "squawk-ami" {
  most_recent = true
  owners = ["self"]

  filter {
    name = "name"
    values = ["squawk-*"]
  }
}

resource "aws_security_group" "squawk" {
  name = "${var.shared["env"]}-squawk"
  vpc_id = "${data.terraform_remote_state.vpc.vpc_id}"

  egress {
    from_port = "0"
    to_port = "65535"
    protocol = "tcp"
    security_groups = ["${data.terraform_remote_state.ret.ret_security_group_id}"]
  }

  egress {
    from_port = "0"
    to_port = "65535"
    protocol = "udp"
    security_groups = ["${data.terraform_remote_state.ret.ret_security_group_id}"]
  }

  egress {
    from_port = "80"
    to_port = "80"
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = "443"
    to_port = "443"
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Papertrail
  egress {
    from_port = "28666"
    to_port = "28666"
    protocol = "tcp"
    cidr_blocks = ["169.46.82.160/27"]
  }

  # NTP
  egress {
    from_port = "123"
    to_port = "123"
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH
  ingress {
    from_port = "22"
    to_port = "22"
    protocol = "tcp"
    security_groups = ["${data.terraform_remote_state.bastion.bastion_security_group_id}"]
  }

  # WebRTC
  ingress {
    from_port = "0"
    to_port = "65535"
    protocol = "udp"
    security_groups = ["${data.terraform_remote_state.ret.ret_security_group_id}"]
  }
}

resource "aws_iam_role" "squawk" {
  name = "${var.shared["env"]}-squawk"
  assume_role_policy = "${var.shared["ec2_role_policy"]}"
}

resource "aws_iam_role_policy_attachment" "squawk-base-policy" {
  role = "${aws_iam_role.squawk.name}"
  policy_arn = "${data.terraform_remote_state.base.base_policy_arn}"
}

resource "aws_iam_instance_profile" "squawk" {
  name = "${var.shared["env"]}-squawk"
  role = "${aws_iam_role.squawk.id}"
}

resource "aws_launch_configuration" "squawk" {
  image_id = "${data.aws_ami.squawk-ami.id}"
  instance_type = "${var.squawk_instance_type}"
  security_groups = ["${aws_security_group.squawk.id}"]
  key_name = "${data.terraform_remote_state.base.mr_ssh_key_id}"
  iam_instance_profile = "${aws_iam_instance_profile.squawk.id}"
  associate_public_ip_address = false
  lifecycle { create_before_destroy = true }
}

resource "aws_autoscaling_group" "squawk" {
  name = "${var.shared["env"]}-squawk"
  launch_configuration = "${aws_launch_configuration.squawk.id}"
  availability_zones = ["${data.aws_availability_zones.all.names}"]
  vpc_zone_identifier = ["${data.terraform_remote_state.vpc.private_subnet_ids}"]

  min_size = "${var.min_squawk_servers}"
  max_size = "${var.max_squawk_servers}"

  lifecycle { create_before_destroy = true }
  tag { key = "env", value = "${var.shared["env"]}", propagate_at_launch = true }
  tag { key = "host-type", value = "${var.shared["env"]}-squawk", propagate_at_launch = true }
}
