--- aws.nvim – AWS Console URL builder
--- Maps CloudFormation ResourceType + physical_id + region → console URL.
--- Returns nil for types that have no stable console deep-link.
local M = {}

--- Percent-encode a string (RFC 3986 unreserved chars left as-is).
---@param s string
---@return string
local function pct_encode(s)
  return s:gsub("([^%w%-%.%_%~])", function(c)
    return string.format("%%%02X", c:byte())
  end)
end

--- CloudWatch Logs uses a non-standard double-encoding for slashes in the fragment.
--- "/" → "$252F",  "#" → "$2523"
---@param s string
---@return string
local function cw_logs_encode(s)
  -- strip trailing ":*" that appears when the physical_id is an ARN
  s = s:gsub(":*$", "")
  s = s:gsub("#", "$2523")
  s = s:gsub("/", "$252F")
  return s
end

-------------------------------------------------------------------------------
-- URL builders keyed by ResourceType
-- Each entry is a function(physical_id, region) -> string|nil
-------------------------------------------------------------------------------

---@type table<string, fun(id: string, region: string): string|nil>
local builders = {

  ["AWS::S3::Bucket"] = function(id, region)
    return "https://s3.console.aws.amazon.com/s3/buckets/" .. id .. "?region=" .. region
  end,

  ["AWS::Lambda::Function"] = function(id, region)
    return "https://" .. region .. ".console.aws.amazon.com/lambda/home" .. "?region=" .. region .. "#/functions/" .. id
  end,

  ["AWS::IAM::Role"] = function(id, _region)
    -- physical_id is role name (may include a path like "aws-service-role/.../RoleName")
    local name = id:match("([^/]+)$") or id
    return "https://console.aws.amazon.com/iam/home?#/roles/" .. name
  end,

  ["AWS::IAM::Policy"] = function(id, _region)
    -- physical_id is the full policy ARN
    return "https://console.aws.amazon.com/iam/home?#/policies/" .. id
  end,

  ["AWS::IAM::ManagedPolicy"] = function(id, _region)
    return "https://console.aws.amazon.com/iam/home?#/policies/" .. id
  end,

  ["AWS::IAM::InstanceProfile"] = function(id, _region)
    local name = id:match("([^/]+)$") or id
    return "https://console.aws.amazon.com/iam/home?#/instanceprofiles/" .. name
  end,

  ["AWS::CloudFront::Distribution"] = function(id, _region)
    return "https://console.aws.amazon.com/cloudfront/v4/home#/distributions/" .. id
  end,

  ["AWS::Logs::LogGroup"] = function(id, region)
    local encoded = cw_logs_encode(id)
    return "https://"
      .. region
      .. ".console.aws.amazon.com/cloudwatch/home"
      .. "?region="
      .. region
      .. "#logsV2:log-groups/log-group/"
      .. encoded
  end,

  ["AWS::DynamoDB::Table"] = function(id, region)
    return "https://"
      .. region
      .. ".console.aws.amazon.com/dynamodbv2/home"
      .. "?region="
      .. region
      .. "#table?name="
      .. id
  end,

  ["AWS::SQS::Queue"] = function(id, region)
    -- physical_id is the full queue URL
    local encoded = pct_encode(id)
    return "https://"
      .. region
      .. ".console.aws.amazon.com/sqs/v2/home"
      .. "?region="
      .. region
      .. "#/queues/"
      .. encoded
  end,

  ["AWS::SNS::Topic"] = function(id, region)
    -- physical_id is the full ARN
    return "https://console.aws.amazon.com/sns/v3/home" .. "?region=" .. region .. "#/topic/" .. id
  end,

  ["AWS::EC2::Instance"] = function(id, region)
    return "https://"
      .. region
      .. ".console.aws.amazon.com/ec2/home"
      .. "?region="
      .. region
      .. "#InstanceDetails:instanceId="
      .. id
  end,

  ["AWS::EC2::SecurityGroup"] = function(id, region)
    return "https://"
      .. region
      .. ".console.aws.amazon.com/vpc/home"
      .. "?region="
      .. region
      .. "#SecurityGroup:groupId="
      .. id
  end,

  ["AWS::EC2::VPC"] = function(id, region)
    return "https://"
      .. region
      .. ".console.aws.amazon.com/vpc/home"
      .. "?region="
      .. region
      .. "#VpcDetails:VpcId="
      .. id
  end,

  ["AWS::EC2::Subnet"] = function(id, region)
    return "https://"
      .. region
      .. ".console.aws.amazon.com/vpc/home"
      .. "?region="
      .. region
      .. "#SubnetDetails:subnetId="
      .. id
  end,

  ["AWS::EC2::InternetGateway"] = function(id, region)
    return "https://"
      .. region
      .. ".console.aws.amazon.com/vpc/home"
      .. "?region="
      .. region
      .. "#InternetGateway:internetGatewayId="
      .. id
  end,

  ["AWS::EC2::RouteTable"] = function(id, region)
    return "https://"
      .. region
      .. ".console.aws.amazon.com/vpc/home"
      .. "?region="
      .. region
      .. "#RouteTables:routeTableId="
      .. id
  end,

  ["AWS::RDS::DBInstance"] = function(id, region)
    return "https://console.aws.amazon.com/rds/home" .. "?region=" .. region .. "#database:id=" .. id
  end,

  ["AWS::RDS::DBCluster"] = function(id, region)
    return "https://console.aws.amazon.com/rds/home"
      .. "?region="
      .. region
      .. "#database:id="
      .. id
      .. ";is-cluster=true"
  end,

  ["AWS::ECS::Cluster"] = function(id, region)
    -- physical_id is the cluster ARN; extract name after "cluster/"
    local name = id:match("cluster/(.+)$") or id
    return "https://" .. region .. ".console.aws.amazon.com/ecs/v2/clusters/" .. name .. "?region=" .. region
  end,

  ["AWS::ECS::Service"] = function(id, region)
    -- ARN resource: "service/{cluster}/{service}"
    local cluster, service = id:match("service/([^/]+)/([^/]+)$")
    if not cluster then
      return nil
    end
    return "https://"
      .. region
      .. ".console.aws.amazon.com/ecs/v2/clusters/"
      .. cluster
      .. "/services/"
      .. service
      .. "?region="
      .. region
  end,

  ["AWS::ApiGateway::RestApi"] = function(id, region)
    return "https://"
      .. region
      .. ".console.aws.amazon.com/apigateway/main/apis/"
      .. id
      .. "/resources?api="
      .. id
      .. "&region="
      .. region
  end,

  ["AWS::ApiGatewayV2::Api"] = function(id, region)
    return "https://"
      .. region
      .. ".console.aws.amazon.com/apigateway/main/apis/"
      .. id
      .. "/routes?api="
      .. id
      .. "&region="
      .. region
  end,

  ["AWS::StepFunctions::StateMachine"] = function(id, region)
    return "https://"
      .. region
      .. ".console.aws.amazon.com/states/home"
      .. "?region="
      .. region
      .. "#/statemachines/view/"
      .. id
  end,

  ["AWS::SecretsManager::Secret"] = function(id, region)
    -- ARN ends in "-XXXXXX" (6-char random suffix); strip it for the name
    local name = id:match("secret:(.+)$") or id
    name = name:gsub("%-%w%w%w%w%w%w$", "")
    return "https://"
      .. region
      .. ".console.aws.amazon.com/secretsmanager/secret"
      .. "?name="
      .. name
      .. "&region="
      .. region
  end,

  ["AWS::SSM::Parameter"] = function(id, region)
    local encoded = id:gsub("/", "%%2F")
    return "https://"
      .. region
      .. ".console.aws.amazon.com/systems-manager/parameters/"
      .. encoded
      .. "/description?region="
      .. region
  end,

  ["AWS::KMS::Key"] = function(id, region)
    return "https://console.aws.amazon.com/kms/home" .. "?region=" .. region .. "#/kms/keys/" .. id
  end,

  ["AWS::KMS::Alias"] = function(id, region)
    -- physical_id is the alias name, e.g. "alias/my-key"
    return "https://console.aws.amazon.com/kms/home" .. "?region=" .. region .. "#/kms/aliases"
  end,

  ["AWS::ElasticLoadBalancingV2::LoadBalancer"] = function(id, region)
    return "https://"
      .. region
      .. ".console.aws.amazon.com/ec2/home"
      .. "?region="
      .. region
      .. "#LoadBalancer:loadBalancerArn="
      .. id
  end,

  ["AWS::ElasticLoadBalancingV2::TargetGroup"] = function(id, region)
    return "https://"
      .. region
      .. ".console.aws.amazon.com/ec2/home"
      .. "?region="
      .. region
      .. "#TargetGroup:targetGroupArn="
      .. id
  end,

  ["AWS::CloudFormation::Stack"] = function(id, region)
    -- physical_id is the nested stack ARN
    local encoded = pct_encode(id)
    return "https://"
      .. region
      .. ".console.aws.amazon.com/cloudformation/home"
      .. "?region="
      .. region
      .. "#/stacks/stackinfo?stackId="
      .. encoded
  end,

  ["AWS::Events::Rule"] = function(id, region)
    return "https://" .. region .. ".console.aws.amazon.com/events/home" .. "?region=" .. region .. "#/rules/" .. id
  end,

  ["AWS::SNS::Subscription"] = function(_id, _region)
    -- No stable deep-link per subscription
    return nil
  end,
}

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------

--- Return the AWS Console URL for a resource, or nil if not linkable.
---@param resource_type string   e.g. "AWS::Lambda::Function"
---@param physical_id   string
---@param region        string
---@return string|nil
function M.build(resource_type, physical_id, region)
  if not physical_id or physical_id == "" then
    return nil
  end
  -- Skip CDK metadata and custom resources
  if resource_type == "AWS::CDK::Metadata" then
    return nil
  end
  if resource_type:match("^Custom::") then
    return nil
  end

  local builder = builders[resource_type]
  if not builder then
    return nil
  end

  local ok, url = pcall(builder, physical_id, region)
  if ok and type(url) == "string" then
    return url
  end
  return nil
end

--- Returns true when the given resource type has a known console link builder.
---@param resource_type string
---@return boolean
function M.has_link(resource_type)
  if resource_type == "AWS::CDK::Metadata" then
    return false
  end
  if resource_type:match("^Custom::") then
    return false
  end
  return builders[resource_type] ~= nil
end

return M
