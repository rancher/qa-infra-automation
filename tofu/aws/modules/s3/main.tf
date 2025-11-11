resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_policy" "this" {
  count = var.block_public_access ? 0 : 1
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.this.json

  depends_on = [
    aws_s3_bucket_public_access_block.this
  ]
}

resource "aws_s3_bucket_object" "this" {
  count = var.file_name != "" && var.file_path != "" ? 1 : 0
  bucket = aws_s3_bucket.this.id
  key    = var.file_name
  source = var.file_path
}

data "aws_iam_policy_document" "this" {
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
      "${aws_s3_bucket.this.arn}/*",
    ]

    effect = "Allow"
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = var.block_public_access
  block_public_policy     = var.block_public_access
  ignore_public_acls      = var.block_public_access
  restrict_public_buckets = var.block_public_access
}
