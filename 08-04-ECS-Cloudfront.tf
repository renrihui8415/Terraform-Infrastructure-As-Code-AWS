# To apply cloudfront in front of ALB and ECS
# Please refer to files starting with "07-"

# Cloudfront ----------------> S3
# Cloudfront --------> ALB --> ECS (Auto Scaling)

# in this project, 
# ECS only accept requests from ALB
  # who only accept requests from Cloudfront
    # who only accept requests by registered domain name
