import json
import boto3
import urllib3
import datetime

API_KEY = 'INSERT API KEY HERE'
STOCK = 'AMZN'
TARGET = 300
client = boto3.client('sns')

def lambda_handler(event, context):
    http = urllib3.PoolManager()

    r = http.request('GET', f'https://financialmodelingprep.com/stable/holidays-by-exchange?exchange=NASDAQ&apikey={API_KEY}')

    obj = json.loads(r.data.decode('utf-8'))

    holidays = set([x['date'] for x in obj])

	# check if today is a holiday (market closed), if so, skip logic
    if datetime.date.today().isoformat() in holidays:
        return {
            'statusCode': 200,
            'body': ''
        }

    r = http.request('GET', f'https://financialmodelingprep.com/stable/profile?symbol={STOCK}&apikey={API_KEY}')
    # print(r.data.decode('utf-8'))

    obj = json.loads(r.data.decode('utf-8'))

    print(obj)

    price = obj[0]['price']
    distance = TARGET - price
    percent = distance / TARGET * 100

    r = http.request('GET', 'https://zenquotes.io/api/quotes')

    obj = json.loads(r.data.decode('utf-8'))

    print(obj)

    quote = obj[0]['q']
    author = obj[0]['a']

    message = f'Current price of {STOCK} is ${price}, {percent:.2f}% (${distance:.2f}) away from target price of ${TARGET}\n\n'
    message += f'"{quote}"\n -{author}'

    client.publish(
        TopicArn='INSERT SNS TOPIC ARN HERE',
        Message=message
    )

    return {
        'statusCode': 200,
        'body': json.dumps(message)
    }
