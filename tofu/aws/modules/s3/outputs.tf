output "aws_s3_bucket_id" {
  value = aws_s3_bucket.this.id
}

output "aws_s3_object_url" {
  value = [
    for obj in aws_s3_bucket_object.this :
    "https://${aws_s3_bucket.this.bucket}.s3.amazonaws.com/${obj.key}"
  ]
}