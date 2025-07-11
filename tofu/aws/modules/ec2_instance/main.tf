resource "aws_instance" "this" {
    ami = var.ami
    instance_type = var.instance_type
    subnet_id = var.subnet_id
    vpc_security_group_ids = var.security_group_ids
    key_name = var.ssh_key_name
    associate_public_ip_address = var.associate_public_ip 

    root_block_device {
        volume_size = var.volume_size
    }

    tags = {
        Name = var.name
    }

    connection {
        type = "ssh"
        user = var.user_id
        host = var.associate_public_ip ? self.public_ip : self.private_ip
        private_key = file(var.ssh_key)
        timeout = "5m"
    }
}
