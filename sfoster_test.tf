################################
# Variables
################################
# Define the variables for building the Voting Application for Team Tech
# Mandatory variables
variable "access_key" {}
variable "secret_key" {}
variable "internet_cidr_blocks" {
  type = "list"
  }
  variable "team_name" {}
  variable "key_name" {}

   # Optional variables
   variable "region" {
     default = "eu-west-1"
     }
     variable "ami" {
       default = "ami-19888a7f"
       }
       variable "instance_type" {
         default = "t2.micro"
	 }
	 variable "iam_instance_profile" {
	   default = "hackathonS3"
	   }
	   variable "instance_count" {
	     default = 2
	     }
       ################################
       # Data
       ################################
       # Get defined data variables for resources that are already defined
       # Get the Hackathon VPC ID
       data "aws_vpc" "hackathon" {
         tags = [ {"Name" = "Hackathon"} ]
       }

       # Get Security Group ID for hackathonSSHOnly
       data "aws_security_group" "hackathonSSHOnly" {
         name = "HackathonSSHOnly"
         vpc_id = "${data.aws_vpc.hackathon.id}"
       }


       # Get the available Public subnets for the Hackathon
       data "aws_subnet_ids" "hackathonPublicSubnetIds" {
         vpc_id = "${data.aws_vpc.hackathon.id}"
         tags {
           Tier = "Hackathon_Public"
         }
       }
       ################################
       # Provider Setup
       ################################
       # AWS Provider setup
       provider "aws" {

         access_key = "${var.access_key}"
         secret_key = "${var.secret_key}"
         region = "${var.region}"

       }

       # Security Group for External Access to Voting
resource "aws_security_group" "voting_external_sg" {

 name = "${var.team_name}-voting-lb-sg"
 description = "Access to ${var.team_name} Voting"
 vpc_id = "${data.aws_vpc.hackathon.id}"

 tags {
   Name = "${var.team_name}-voting-lb-sg",
   Team = "${var.team_name}"
 }

}
# Security Group Rule to access the Load Balancer using HTTP from a specific Internet Address
resource "aws_security_group_rule" "http_lb_access" {

 security_group_id = "${aws_security_group.voting_external_sg.id}"
 type = "ingress"
 protocol = "tcp"
 from_port = 80
 to_port = 80
 cidr_blocks = "${var.internet_cidr_blocks}"

}

# Security Group for Voting Application Access
resource "aws_security_group" "voting_app_sg" {

 name = "${var.team_name}-voting-app-sg"
 description = "Access to ${var.team_name} Voting"
 vpc_id = "${data.aws_vpc.hackathon.id}"

 tags {
   Name = "${var.team_name}-voting-app-sg",
   Team = "${var.team_name}"
 }

}
# Security Group Rule allowing access to the App Servers from the Load Balancer
resource "aws_security_group_rule" "http_access_rule" {

 security_group_id = "${aws_security_group.voting_app_sg.id}"
 type = "ingress"
 protocol = "tcp"
 from_port = 8080
 to_port = 8080
 source_security_group_id = "${aws_security_group.voting_external_sg.id}"

}
# Voting Application Load Balancer
resource "aws_alb" "voting_alb" {
  name = "vote-for-${var.team_name}"
  internal = false
  security_groups = [
    "${aws_security_group.voting_external_sg.id}"
  ]
  subnets = ["${data.aws_subnet_ids.hackathonPublicSubnetIds.ids}"]

  tags {
    Team = "${var.team_name}"
  }

}
# Target Group
resource "aws_alb_target_group" "voting_alb_target_group" {

  name = "voting-app-tg"
  port = 8080
  protocol = "HTTP"
  vpc_id = "${data.aws_vpc.hackathon.id}"

  health_check {
    path = "/health"
  }

  tags {
    Team = "${var.team_name}"
  }

}
# Target Group Attachments (1 per EC2 instance)
resource "aws_alb_target_group_attachment" "voting_zonea_alb_tg_attachment" {
  count = "${var.instance_count}"
  target_group_arn = "${aws_alb_target_group.voting_alb_target_group.arn}"
  port = 8080
  target_id = "${element(aws_instance.voting_server.*.id, count.index)}"
}
# Load Balancer Listener
resource "aws_alb_listener" "voting_alb_listener" {
  load_balancer_arn = "${aws_alb.voting_alb.arn}"
  port = 80
  protocol = "HTTP"
  default_action {
    target_group_arn = "${aws_alb_target_group.voting_alb_target_group.arn}"
    type = "forward"
  }
}
################################
# EC2 Instances
################################
# Voting Application Server
resource "aws_instance" "voting_server" {

  count = "${var.instance_count}"
  ami = "${var.ami}"
  instance_type = "${var.instance_type}"
  associate_public_ip_address = "true"
  iam_instance_profile = "${var.iam_instance_profile}"
  subnet_id = "${element(data.aws_subnet_ids.hackathonPublicSubnetIds.ids, count.index)}"
  key_name = "${var.key_name}"
  vpc_security_group_ids = [
    "${data.aws_security_group.hackathonSSHOnly.id}",
    "${aws_security_group.voting_app_sg.id}"
  ]
  tags {
    Name = "${var.team_name}-${count.index+1}",
    Team = "${var.team_name}"
  }

}
