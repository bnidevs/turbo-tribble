import json
import os
from urllib.parse import parse_qs, unquote_plus

import boto3

sns = boto3.client("sns")

TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]
DEFAULT_MSG = "ping-me default message"


def lambda_handler(event, context):
    qs = parse_qs(event.get("rawQueryString", ""))
    raw = qs.get("msg", [DEFAULT_MSG])[0]
    msg = unquote_plus(raw)

    response = sns.publish(
        TopicArn=TOPIC_ARN,
        Message=msg,
        Subject="ping-me",
    )

    return {
        "statusCode": 200,
        "body": json.dumps({
            "message": msg,
            "messageId": response["MessageId"],
        }),
    }
