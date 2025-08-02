import boto3
import os

ssm_client = boto3.client('ssm')
sns_client = boto3.client('sns')

INSTANCE_ID = os.environ.get('INSTANCE_ID')
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN')

def handler(event, context):
    action = event.get('action')
    
    if action == 'restart_service':
        try:
            response = ssm_client.send_command(
                InstanceIds=[INSTANCE_ID],
                DocumentName='AWS-RunShellScript',
                Parameters={'commands': ['sudo systemctl restart httpd']}
            )
            
            message = f"Remediation successful: Sent command to restart httpd on instance {INSTANCE_ID}."
            
        except Exception as e:
            message = f"Remediation failed for instance {INSTANCE_ID}: {str(e)}"
            
    else:
        message = f"Unknown action '{action}' requested. No remediation performed."

    # Notify via SNS
    sns_client.publish(
        TopicArn=SNS_TOPIC_ARN,
        Message=message,
        Subject="AIOps Self-Healing Notification"
    )
    
    return {"status": "Completed", "message": message}