output "ec2_public_ip" {
  description = "Public IP address of the EC2 instance."
  value       = aws_instance.app_server.public_ip
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket for ML artifacts."
  value       = aws_s3_bucket.ml_artifacts.id
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for notifications."
  value       = aws_sns_topic.notifications.arn
}

output "app_log_group_name" {
    description = "Name of the CloudWatch Log Group for the application."
    value = aws_cloudwatch_log_group.app_logs.name
}