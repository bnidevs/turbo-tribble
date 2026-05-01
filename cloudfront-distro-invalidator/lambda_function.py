import boto3
import time

codepipeline = boto3.client('codepipeline')

def lambda_handler(event, context):
    job_id = event['CodePipeline.job']['id']

    try:
        # STRICT LOGIC START
        cf = boto3.client('cloudfront')
        # this is NOT the ARN
        dist_id = 'INSERT CLOUDFRONT DISTRIBUTION ID HERE'
        resp = cf.create_invalidation(
            DistributionId=dist_id,
            InvalidationBatch={
                'Paths': {'Quantity': 1, 'Items': ['/*']},
                'CallerReference': str(time.time()),
            },
        )

        # REMOVE THIS LINE IF ONLY USING STRICT LOGIC
        codepipeline.put_job_success_result(jobId=job_id)
        
        return {
            'statusCode': 200,
            'invalidation_id': resp['Invalidation']['Id'],
            'status': resp['Invalidation']['Status'],
        }

        # STRICT LOGIC END
    except Exception as e:
        codepipeline.put_job_failure_result(
            jobId=job_id,
            failureDetails={
                'type': 'JobFailed',
                'message': str(e)
            }
        )
