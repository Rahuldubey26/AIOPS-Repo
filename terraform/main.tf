#### **`terraform/main.tf`**

provider "aws" {
  region = var.aws_region
}

# --- Networking ---
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.project_name}-public-subnet"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# --- Security ---
resource "aws_security_group" "ec2_sg" {
  name        = "${var.project_name}-ec2-sg"
  vpc_id      = aws_vpc.main.id
  description = "Allow HTTP and SSH inbound"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # WARNING: Open to the world. Restrict to your IP in production.
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- IAM Roles ---
resource "aws_iam_role" "ec2_role" {
  name = "${var.project_name}-ec2-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_ssm_policy" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# --- EC2 Instance (Our App Server) ---
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_instance" "app_server" {
  ami           = data.aws_ami.amazon_linux_2.id
  instance_type = var.instance_type
  subnet_id     = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd stress
              systemctl start httpd
              systemctl enable httpd
              echo "<h1>Hello from AIOps Demo Server</h1>" > /var/www/html/index.html
              
              # Simple log generator
              yum install -y ruby
              wget https://s3.amazonaws.com/aws-cloudwatch/downloads/latest/awslogs-agent-setup.py
              chmod +x ./awslogs-agent-setup.py
              # Note: The CloudWatch agent will be configured to send logs to the group created below
              # In a real scenario, you would automate the agent configuration as well.
              EOF

  tags = {
    Name = "${var.project_name}-app-server"
  }
}

# --- S3 Bucket for ML Models ---
resource "aws_s3_bucket" "ml_artifacts" {
  bucket = "${var.project_name}-ml-artifacts-${random_id.bucket_suffix.hex}"
  acl    = "private"
  versioning {
    enabled = true
  }
}

resource "random_id" "bucket_suffix" {
  byte_length = 8
}

# --- CloudWatch Log Group for the App ---
resource "aws_cloudwatch_log_group" "app_logs" {
  name = "/${var.project_name}/app"
  retention_in_days = 7
}

# --- IAM Role for Lambda Functions ---
resource "aws_iam_role" "lambda_exec_role" {
  name = "${var.project_name}-lambda-exec-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_policy" "lambda_policy" {
  name = "${var.project_name}-lambda-policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect   = "Allow",
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Action   = ["s3:GetObject"],
        Effect   = "Allow",
        Resource = "${aws_s3_bucket.ml_artifacts.arn}/*"
      },
      {
        Action = [
          "logs:StartQuery",
          "logs:GetQueryResults"
        ],
        Effect   = "Allow",
        Resource = "*" # Restrict in production
      },
      {
        Action   = ["ssm:SendCommand"],
        Effect   = "Allow",
        Resource = [
          "arn:aws:ssm:*:*:document/AWS-RunShellScript",
          "arn:aws:ec2:*:*:instance/${aws_instance.app_server.id}"
        ]
      },
      {
        Action   = ["sns:Publish"],
        Effect   = "Allow",
        Resource = aws_sns_topic.notifications.arn
      }
    ]
  })
}

# terraform/main.tf (ADD THIS NEW RESOURCE)

resource "aws_lambda_layer_version" "ml_libraries_layer" {
  # The zip file will be created and uploaded by our CI/CD pipeline
  filename   = "../src/lambda_layer/ml_libraries_layer.zip" 
  layer_name = "${var.project_name}-ml-libraries"

  # The libraries will be available for Python 3.9 runtimes
  compatible_runtimes = ["python3.9"]

  # Keep a reference to the source code hash to update the layer when the zip changes
  source_code_hash = filebase64sha256("../src/lambda_layer/ml_libraries_layer.zip")
}

resource "aws_iam_role_policy_attachment" "lambda_attach" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# --- SNS Topic for Notifications ---
resource "aws_sns_topic" "notifications" {
  name = "${var.project_name}-notifications"
}

# --- Placeholder for Lambda functions (will be deployed via CI/CD) ---
# We still define them here so Terraform is aware of them.

resource "aws_lambda_function" "anomaly_detector" {
  function_name = "${var.project_name}-anomaly-detector"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "app.handler"
  runtime       = "python3.9"
  timeout       = 30
  
  filename = "../src/lambda_functions/anomaly_detection_placeholder.zip" # Placeholder
  source_code_hash = filebase64sha256("../src/lambda_functions/anomaly_detection_placeholder.zip")

  layers = [aws_lambda_layer_version.ml_libraries_layer.arn]
  
  environment {
    variables = {
      S3_BUCKET = aws_s3_bucket.ml_artifacts.bucket
      MODEL_KEY = "models/isolation_forest_model.pkl"
    }
  }
  depends_on = [
    aws_lambda_layer_version.ml_libraries_layer
  ]
}

resource "aws_lambda_function" "log_analyzer" {
  function_name = "${var.project_name}-log-analyzer"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "app.handler"
  runtime       = "python3.9"
  timeout       = 30

  filename = "../src/lambda_functions/log_analyzer_placeholder.zip" # Placeholder
  source_code_hash = filebase64sha256("../src/lambda_functions/log_analyzer_placeholder.zip")
  
  environment {
    variables = {
      LOG_GROUP_NAME = aws_cloudwatch_log_group.app_logs.name
    }
  }
}

resource "aws_lambda_function" "remediation_handler" {
  function_name = "${var.project_name}-remediation-handler"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "app.handler"
  runtime       = "python3.9"
  timeout       = 30

  filename = "../src/lambda_functions/remediation_handler_placeholder.zip" # Placeholder
  source_code_hash = filebase64sha256("../src/lambda_functions/remediation_handler_placeholder.zip")

  environment {
    variables = {
      INSTANCE_ID     = aws_instance.app_server.id
      SNS_TOPIC_ARN   = aws_sns_topic.notifications.arn
    }
  }
}


# --- Step Functions State Machine ---
resource "aws_sfn_state_machine" "self_healing_workflow" {
  name     = "${var.project_name}-self-healing-workflow"
  role_arn = aws_iam_role.sfn_role.arn

  definition = <<EOF
{
  "Comment": "Self-healing workflow for AIOps",
  "StartAt": "AnalyzeLogs",
  "States": {
    "AnalyzeLogs": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${aws_lambda_function.log_analyzer.function_name}:$LATEST",
        "Payload": {
          "instance_id.$": "$.detail.instance-id"
        }
      },
      "Next": "IsRootCauseFound"
    },
    "IsRootCauseFound": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$.Payload.summary",
          "StringMatches": "*error*",
          "Next": "RemediateApplication"
        }
      ],
      "Default": "NotifyAndStop"
    },
    "RemediateApplication": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${aws_lambda_function.remediation_handler.function_name}:$LATEST",
        "Payload": {
          "action": "restart_service"
        }
      },
      "End": true
    },
    "NotifyAndStop": {
      "Type": "Task",
      "Resource": "arn:aws:states:::sns:publish",
      "Parameters": {
        "TopicArn": "${aws_sns_topic.notifications.arn}",
        "Message": {
          "Input.$": "$"
        }
      },
      "End": true
    }
  }
}
EOF
}

resource "aws_iam_role" "sfn_role" {
  name = "${var.project_name}-sfn-exec-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "states.${var.aws_region}.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "sfn_policy" {
  name = "${var.project_name}-sfn-policy"
  role = aws_iam_role.sfn_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["lambda:InvokeFunction"],
        Resource = [
          aws_lambda_function.log_analyzer.arn,
          aws_lambda_function.remediation_handler.arn
        ]
      },
      {
        Effect   = "Allow",
        Action   = ["sns:Publish"],
        Resource = aws_sns_topic.notifications.arn
      }
    ]
  })
}

# --- CloudWatch Alarm to Trigger Workflow ---
resource "aws_cloudwatch_metric_alarm" "high_cpu_alarm" {
  alarm_name          = "${var.project_name}-high-cpu"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "70" # Set a threshold that you can easily trigger for testing
  alarm_description   = "This metric monitors ec2 cpu utilization"
  
  dimensions = {
    InstanceId = aws_instance.app_server.id
  }

  alarm_actions = [aws_sns_topic.notifications.arn] # Initially, just notify. We will add the Step Function trigger later.
}