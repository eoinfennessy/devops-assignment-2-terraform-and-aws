- Move RDS to private subnet
- Create bastion host and associated security groups
    - SG to SSH to bastion from host and SG to SSH to EC2 instances from bastion
- Create new, simplified app
    - Include route to get instance metadata and log to log file.
- Create new AMI
    - Install Python 3.11?
    - Add updated monitor script and setup cron job to push metrics to CloudWatch
    - Add LabInstanceProfile to EC2 launch template
- Write Python test to demonstrate working load balancer
    - Use asyncio, aiohttp, logging
    - Use "base_request_id" concatenated with index of request_count

## Nice to Haves
- TLS connection
- Route to upload image to S3 (boto3 and IAM)
- Lambda function to update image on upload to S3


## Zoom Call
9 sections in report (one extra for additional functionality)
Screenshots of pertinent info
Put references to sources
Label screenshots
Don't write too much text
Auto-scaling - outstanding: Vary functionality - different metrics

.aws config setup for EC2 for region - or specify region with boto3 i.e. boto3.resource("s3", region="us-east")

Quiz: 

Presentation: demo auto scaling and load balancing and extra functionality


 