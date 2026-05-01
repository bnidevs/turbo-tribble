import json
import boto3

def lambda_handler(event, context):
    client = boto3.client('sns')
    
    qs = event['rawQueryString'].split('&')
    
    msg = 'ping-me default message'
    
    for k in qs:
        ks = k.split('=')
        if ks[0] == 'msg':
            msg = 'ping-me message: ' + ks[1]
    
    return client.publish(
        TargetArn='INSERT SNS TOPIC ARN HERE',
        Message=json.dumps({'default': json.dumps(msg)}),
        MessageStructure='json'
    )
