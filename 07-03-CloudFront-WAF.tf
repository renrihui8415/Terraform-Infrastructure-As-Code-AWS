#!! things we should know about WAF
# if we wish the cf DNS name (like 3425s.cloudfront.net) can't access cf
# or if we wish the alb DNS name (like 1241.elb.amazonaws.com) can't access alb
# WAF can be applied to check and forbid any request ending with cloudfront.net or elb.amazonaws.com

# for ALB, SG can also help to block any ip range other than cloudfront edge servers to access it.

# the rules for cf in this project:
#1 AWSManagedRulesAmazonIpReputationList
#2 AWSManagedRulesSQLiRuleSet
#3 Custom-BlockCFDNS (to block any host header ending with "cloudfront.net")
#4 Custom-AWSRateBasedIPRule

#=============================================================
#1 to create selected rules for the cloudfront
  #1.1 to use variable to gather selected managed rule groups together
  #1.2 to create dynamic rule block in step 2 for WAF building
#2 to create WAF
  #2.1 to add AWS managed rule groups using dynamic block
  #2.2 to add custom rules in to WAF as well
#3 to attach WAF to cloudfront 
#=============================================================
#1.1 below is to create selected rules for the cloudfront
# choose what rules you'd like for the cloudfront
#Note: 
# the rule statement are divided into 2 categories: rule-group and non-rule-group
# rule-group: there are default rule action (like, "allow" or "block")
# we can use override_action to override the default action (like counting the "bad" request instead of blocking it)
# the count action is more for testing purpose
# none-rule-group: we define action as we wish (like, "allow" and "block")
# as these two rule groups have different compiling structures
# we need to add them separately into WAF
variable "rules" {
  type    = list
  default = [
    {
      name = "AWSManagedRulesABCD"
      managed_rule_group_statement_name = "AWSManagedRulesABCD"
      managed_rule_group_statement_vendor_name = "AWS"
      metric_name = "bot"
    },
    {
      name = "AWSManagedRulesEFGH"
      managed_rule_group_statement_name = "AWSManagedRulesEFGH"
      managed_rule_group_statement_vendor_name = "AWS"
      metric_name = "sql"
    }
  ]
}
locals {
  total_managed_rules=length(var.rules)
  # count how many managed rules we use for this project
  # it is used for the following rules' priority.
  # priority differs in projects.
  # Do modify this variable based on your own project.
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
#==============================================================
  dynamic "rule" {
    for_each = var.rules
    content {
      name = rule.value.name
      priority = rule.key +1
      # if for_each refers to a list
      # dynamic var.key = index
      # priority can be automatically added according to its order in var.rules
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
  
  #==============================================================
  rule {
    name     = "${local.prefix}-WAF-Validates-Host-Header"
    priority = local.total_managed_rules+1

    action {
      block {}
    }
    #if the request matching the rule
    #block the requests

    # "action" can only be used for non-rule-group-statement
    # while, override_action can only used for rule-group-statement
    statement {
      byte_match_statement {
        field_to_match {
          single_header {
            name = "host"        
          }
        }        
        positional_constraint = "CONTAINS"
        search_string = "cloudfront.net"
        text_transformation {
          priority = 1
          type = "LOWERCASE"
        } 
      }   
    }

    visibility_config {
      cloudwatch_metrics_enabled = false
      metric_name                = "${local.prefix}-waf-validates-host-header"
      sampled_requests_enabled   = false
    }
  }
  #==============================================================
  rule {
    name     = "AWSRateBasedIPRule"
    priority = local.total_managed_rules+2

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
            country_codes = local.geo_restriction
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

  visibility_config {
    cloudwatch_metrics_enabled = false
    metric_name                = "${local.prefix}-waf-acl"
    sampled_requests_enabled   = false
  }
  tags = {
    Name = "${local.prefix}-waf-acl"
  }
}

#3 to attach WAF to cloudfront
# in resource of Cloudfront, add WAF arn for "web_acl_id".
