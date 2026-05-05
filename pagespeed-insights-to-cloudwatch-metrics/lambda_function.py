import os
import urllib.request
import urllib.parse
import json
import boto3

TARGET_URLS = [
    'INSERT TARGET URL HERE'
]

TARGET_STRATEGIES = [
    'mobile',
    'desktop'
]

CATEGORIES = [
    'accessibility',
    'best-practices',
    'performance',
    'seo'
]

cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    API_KEY = 'INSERT PAGESPEED INSIGHTS API KEY HERE'

    metric_data = []

    for target_url in TARGET_URLS:
        for target_strategy in TARGET_STRATEGIES:
            for category in CATEGORIES:
                print(target_url, target_strategy, category)

                base_url = "https://www.googleapis.com/pagespeedonline/v5/runPagespeed"
                params = {
                    "url": target_url,
                    "strategy": target_strategy,
                    "category": category
                }
                if API_KEY:
                    params["key"] = API_KEY

                url = f"{base_url}?{urllib.parse.urlencode(params)}"

                try:
                    with urllib.request.urlopen(url) as response:
                        data = json.loads(response.read().decode())

                        score = data['lighthouseResult']['categories'][category]['score']
                        print(f"{category} Score for {target_url} on {target_strategy}: {score}")

                        metric_data.append({
                            'MetricName': 'LighthouseScore',
                            'Dimensions': [
                                {'Name': 'URL', 'Value': target_url},
                                {'Name': 'Strategy', 'Value': target_strategy},
                                {'Name': 'Category', 'Value': category},
                            ],
                            'Value': score * 100,
                            'Unit': 'None'
                        })

                except Exception as e:
                    print(f"Error fetching PageSpeed data: {str(e)}")

    # Batch publish — PutMetricData accepts up to 1000 per call, you have 16
    if metric_data:
        cloudwatch.put_metric_data(
            Namespace='PageSpeed Insights',
            MetricData=metric_data
        )
        print(f"Published {len(metric_data)} metrics to CloudWatch")

    return {
        'statusCode': 200,
        'body': json.dumps({'metrics_published': len(metric_data)})
    }
