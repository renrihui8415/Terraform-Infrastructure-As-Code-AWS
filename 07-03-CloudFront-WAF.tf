#!! things we should know about WAF
# it shows that if we use the domain_name (like 1234567890.cloudfront.net) to visit 
# the website, WAF won't check... 
# well, don't ever expose domain from cloudfront to public
#=============================================================
#1 to create selected rules for the cloudfront
  #1.1 to use variable to gather selected managed rule groups together
  #1.2 to create dynamic rule block in step 2 for WAF building
#2 to create WAF
#=============================================================
#1.1 below is to create selected rules for the cloudfront
# choose what rules you'd like for the cloudfront
#Note: 
# the rule statement are divided into 2 categories: rule-group and non-rule-group
# in rule-group: there are default rule action (like, "allow" or "block" requests from internet)
# we can use override_action to override the default action (like count the "bad" request insteading of blocking it)
# the count action is more for testing purpose
# in none-rule-group: we define action as we wish (like, "allow" and "block")
# as these two groups have different compiling structures
# they won't be gathered into one variables
variable "rules" {
  type    = list
  default = [
    {
      name = "AWSManagedRulesABCD"
      priority = 0
      managed_rule_group_statement_name = "AWSManagedRulesABCD"
      managed_rule_group_statement_vendor_name = "AWS"
      metric_name = "bot"
    },
    {
      name = "AWSManagedRulesEFGH"
      priority = 1
      managed_rule_group_statement_name = "AWSManagedRulesEFGH"
      managed_rule_group_statement_vendor_name = "AWS"
      metric_name = "sql"
    }
  ]
}

#2 below is to use "dynamic" block and add the rules to WAF/ACL
# Note: AWS WAF is available globally for CloudFront distributions, 
# but you must use the Region US East (N. Virginia) to create your web ACL 
# and any resources used in the web ACL, 
# such as rule groups, IP sets, and regex pattern sets. 
# Some interfaces offer a region choice of "Global (CloudFront)", 
# choosing this is identical to choosing Region US East (N. Virginia) 
# or "us-east-1".
resource "aws_wafv2_web_acl" "example" {
  provider    = "here is the provider in us-east-1"
  name        = "${local.prefix}-waf-acl"
  description = "Cloudfront rate based, Bot, SQL injection"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }
  #Note: this "default_action" is not the default rule action we mentioned in the above for 
  # AWS managed rule group statement
  # it means:
  # if internet request doesn't match any of the following rules
  # then WAF will forward/allow the request

  rule {
    name     = "AWSRateBasedIPRule"
    priority = 3

    action {
      block {}
    }
    #if the request matching the rule
    #block the requests

    # "action" can only be used for non-rule-group-statement
    # while, "override_action" can only used for rule-group-statement
    # because rule-group-statement already has its own default rule action
    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"

        scope_down_statement {
          geo_match_statement {
            country_codes = ["US", "CA"]
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = false
      metric_name                = "${local.prefix}-waf-acl-rate"
      sampled_requests_enabled   = false
    }
  }
  
  dynamic "rule" {
    for_each = toset(var.rules)
    content {
      name = rule.value.name
      priority = rule.value.priority
      override_action {
        #count {}
          # if we choose count, WAF only count matching requests
          # WAF won't block them
          # use case: testing environment
        none {}
          # do not override the rule group action 
          # the original/default rule group action can be found in aws official docs
      }
      statement {
        managed_rule_group_statement {
          name = rule.value.managed_rule_group_statement_name
          vendor_name = rule.value.managed_rule_group_statement_vendor_name
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = false
        metric_name                = join("-", ["${local.prefix}-waf-acl", rule.value.metric_name])
        sampled_requests_enabled   = false
      }
    }
  }
  tags = {
    Name = "${local.prefix}-waf-acl"
  }

  visibility_config {
    cloudwatch_metrics_enabled = false
    metric_name                = "${local.prefix}-waf-acl"
    sampled_requests_enabled   = false
  }
}


