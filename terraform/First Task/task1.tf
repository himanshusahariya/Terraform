# Declaring Provider
provider "aws" {
  region = "ap-south-1"
 // your profile for AWS here.
 profile = "honey"   
}


#Creating Key Pair
resource "aws_key_pair" "mykey"{
  key_name = "mykey9521"
  // provide your public key here.
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDIL6U9bNsDgxYNKt9woWSbU/bLnNRP/vdxUBlS4oYee2FeF/H1+iRhjDSfavavnp64tavHswo6UWF63FR0YgJbv6g0GC0GqAuMc9GT4ZDQk/KWWuY5CfDfPcW5Aj2fgirqvZpLgkDBrbHc/dZ3Vc3QZztcscP0FwnQ8/y5ij3Plvvb5WLvBmaa5xlGpj75Dcxk59LEb4V33KdUHA3yXc4K+7akU5AAuoOGKvgRHqrcnNxO40JPjitQQLPHfzefSyBzEUQf9ghODTM6qooMkAL/d/UDI/uEHPosnKFD9qDKIDwRMf+nTp1JT0p7Cnbvpi/7MbgAHdILXJ+tHaCPqn4H himanshu@Himanshu"
}
output "Key_Name" {
  value = aws_key_pair.mykey.key_name
}


# Creating Security Group
resource "aws_security_group" "allow_traffic" {
  name        = "allowed_traffic"
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
 ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
}
output "Security_Group_Name" {
  value = aws_security_group.allow_traffic.name
}


#Creation of instance is done in this block.
resource "aws_instance" "ins1"{
depends_on = [
    aws_key_pair.mykey,
    aws_security_group.allow_traffic,
  ]

  ami             = "ami-005956c5f0f757d37" 
  instance_type   = "t2.micro"
  key_name        = aws_key_pair.mykey.key_name
  security_groups = [aws_security_group.allow_traffic.name]
  
   tags = {
    Name = "teraOS"
 }
}
output "Instance_ID" {
    value = aws_instance.ins1.id
}


# Creation of Extra EBS Volume
resource "aws_ebs_volume" "vol1" {
  availability_zone = aws_instance.ins1.availability_zone
  size              = 1
  tags = {
    Name = "pd1"
  }
} 


# Attachment of the Extra EBS volume to instance. 
resource "aws_volume_attachment" "vol_at" {
 depends_on = [
    aws_ebs_volume.vol1,
    aws_instance.ins1,
  ]
  device_name  = "/dev/sdh"
  volume_id    = aws_ebs_volume.vol1.id
  instance_id  = aws_instance.ins1.id
  force_detach = true
}


# Creating Webserver in remote instance and copying code from github to "/var/www/html". 
resource "null_resource" "null1" {
  depends_on = [
      aws_volume_attachment.vol_at,   
]
  connection {
    type        = "ssh"
    user        = "ec2-user"
// your private key path inside file() block.
    private_key = file("H:/Hybrid Cloud/terraform/First Task/SSH-Key")
    host        = aws_instance.ins1.public_ip
  }
  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd git php -y",
      "sudo service httpd start",
      "sudo mkfs.ext4 /dev/xvdh",
      "sudo mount /dev/xvdh /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/himanshusahariya/test-repo.git /var/www/html",
    ]
  }
}


# Variable Declaration For bucket
variable "Unique_Bucket_Name"{
  type = string
  //default = "my-bucket-9521"
}


# AWS S3 Bucket Creation
resource "aws_s3_bucket" "my_bucket" {
  bucket = var.Unique_Bucket_Name
  acl    = "public-read"
}


# Saving name of the bucket to local system
resource "null_resource" "null2" {
  depends_on = [
      aws_s3_bucket.my_bucket,
]
  provisioner "local-exec" {
    command = "echo ${aws_s3_bucket.my_bucket.bucket} > bucket_name.txt"
  } 
}


# Cloning git repository to local system
resource "null_resource" "null" {
  provisioner "local-exec" {
// Provide github repo link here after gitclone to provide your webserver code.
    command = "git clone https://github.com/himanshusahariya/test-repo.git"
  } 
}


# Upload image file on S3 storage from github
resource "aws_s3_bucket_object" "object1" {
  depends_on =[
      null_resource.null,
      aws_s3_bucket.my_bucket
]
  bucket = aws_s3_bucket.my_bucket.bucket
  key    = "bucket_image.jpg"
// Provide path here according To your system's file system
  source = "H:/Hybrid Cloud/terraform/First Task/test-repo/images/Terraform-main-image.jpg"
  acl    = "public-read"
} 


# Cloudfront Distribution Creation
resource "aws_cloudfront_distribution" "s3_distribution" { 
  origin {
    domain_name = aws_s3_bucket.my_bucket.bucket_regional_domain_name
    origin_id   = aws_s3_bucket.my_bucket.bucket
  }
  enabled = true
    default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_s3_bucket.my_bucket.bucket
  forwarded_values {
      query_string = false
        cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
output "cloudfront"{
  value = aws_cloudfront_distribution.s3_distribution.domain_name
}


# Copying object link from cloudfront distribution to webserver file 
resource "null_resource" "nulll" {
  depends_on = [
      aws_cloudfront_distribution.s3_distribution,
      null_resource.null1,   
]
  connection {
    type        = "ssh"
    user        = "ec2-user"
// Your private key path in file() block.
    private_key = file("H:/Hybrid Cloud/terraform/First Task/SSH-Key")
    host        = aws_instance.ins1.public_ip
  }
  provisioner "remote-exec" {
      inline = [ 
        # sudo su << \"EOF\" \n echo \"<img src='${aws_cloudfront_distribution.s3_distribution.domain_name}'>\" >> /var/www/html/test1.php \n \"EOF\"
            "sudo su << EOF",
         "echo \"<img src='http://${aws_cloudfront_distribution.s3_distribution.domain_name}/${aws_s3_bucket_object.object1.key}'>\" >> /var/www/html/test1.php",
          "EOF"
     ]
  }
}


# Copying Webserver link to local system
resource "null_resource" "link" {
     depends_on =[
          aws_instance.ins1,
]
  provisioner "local-exec" {
    command = "echo 'http://${aws_instance.ins1.public_ip}/test1.php' > Link_To_Webpage.txt"
  } 
}