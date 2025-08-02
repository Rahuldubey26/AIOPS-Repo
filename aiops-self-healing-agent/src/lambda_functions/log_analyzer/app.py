import boto3
import os
import time
from datetime import datetime, timedelta

logs_client = boto3.client('logs')
LOG_GROUP_NAME = os.environ.get('LOG_GROUP_NAME')

def handler(event, context):
    # Time window for analysis (5 minutes before the event)
    end_time = datetime.utcnow()
    start_time = end_time - timedelta(minutes=5)
    
    query = f"""
    fields @timestamp, @message
    | filter @message like /(?i)(error|failed|exception|timeout)/
    | sort @timestamp desc
    | limit 20
    """
    
    start_query_response = logs_client.start_query(
        logGroupName=LOG_GROUP_NAME,
        startTime=int(start_time.timestamp()),
        endTime=int(end_time.timestamp()),
        queryString=query
    )
    
    query_id = start_query_response['queryId']
    
    # Poll for results
    response = None
    while response is None or response['status'] in ['Running', 'Scheduled']:
        time.sleep(1)
        response = logs_client.get_query_results(queryId=query_id)
        
    results = response.get('results', [])
    
    if not results:
        return {"summary": "No significant error logs found."}
        
    # Simple summarization
    error_messages = [res[1]['value'] for res in results]
    summary = f"Found {len(error_messages)} potential error(s). First log: '{error_messages[0]}'"
    
    return {"summary": summary}