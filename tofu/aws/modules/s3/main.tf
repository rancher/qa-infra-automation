resource "aws_s3_bucket" "bucket" {
  bucket = var.bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_policy" "bucket_policy" {
  count = var.block_public_access ? 0 : 1
  bucket = aws_s3_bucket.bucket.id
  policy = data.aws_iam_policy_document.policy_document.json

  depends_on = [
    aws_s3_bucket_public_access_block.public_access_block
  ]
}

data "aws_iam_policy_document" "policy_document" {
  statement {
    sid = "PublicReadObjects"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = [
      "s3:GetObject",
    ]

    resources = [
      "${aws_s3_bucket.bucket.arn}/*",
    ]

    effect = "Allow"
  }
}

resource "aws_s3_bucket_public_access_block" "public_access_block" {
  bucket = aws_s3_bucket.bucket.id

  block_public_acls       = var.block_public_access
  block_public_policy     = var.block_public_access
  ignore_public_acls      = var.block_public_access
  restrict_public_buckets = var.block_public_access
}
