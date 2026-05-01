import boto3

BUCKET = 'INSERT BUCKET NAME HERE'
CACHE_CONTROL = 'max-age=31536000'
EXTENSIONS = {'.ico', '.avif', '.jpg', '.jpeg', '.svg'}

s3 = boto3.client('s3')
codepipeline = boto3.client('codepipeline')

def lambda_handler(event, context):
    job_id = event['CodePipeline.job']['id']
    paginator = s3.get_paginator('list_objects_v2')
    updated = 0

    try:
        # STRICT LOGIC START
        for page in paginator.paginate(Bucket=BUCKET):
            for obj in page.get('Contents', []):
                key = obj['Key']
                if not any(key.lower().endswith(ext) for ext in EXTENSIONS):
                    continue

                head = s3.head_object(Bucket=BUCKET, Key=key)

                s3.copy_object(
                    Bucket=BUCKET,
                    Key=key,
                    CopySource={'Bucket': BUCKET, 'Key': key},
                    MetadataDirective='REPLACE',
                    CacheControl=CACHE_CONTROL,
                    ContentType=head.get('ContentType', 'application/octet-stream'),
                    Metadata=head.get('Metadata', {}),
                )
                updated += 1
                print(f'Updated: {key}')
        
        # REMOVE THIS LINE IF ONLY USING STRICT LOGIC
        codepipeline.put_job_success_result(jobId=job_id)

        return {'updated': updated}
        # STRICT LOGIC END
    except Exception as e:
        codepipeline.put_job_failure_result(
            jobId=job_id,
            failureDetails={
                'type': 'JobFailed',
                'message': str(e)
            }
        )
