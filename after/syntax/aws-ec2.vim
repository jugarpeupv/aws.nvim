" aws.nvim – syntax highlighting for the aws-ec2 filetype
syntax clear

" Stop regex matching past column 200 to avoid lag
setlocal synmaxcol=200

" ── Separators ───────────────────────────────────────────────────────────────
syntax match AwsEc2Sep         /^-\+$/

" ── Titles ───────────────────────────────────────────────────────────────────
syntax match AwsEc2Title       /^EC2  .*/

" ── Filter / loading badges ──────────────────────────────────────────────────
syntax match AwsEc2Filter      /\[filter:[^\]]*\]/
syntax match AwsEc2Loading     /\[loading[^\]]*\]/

" ── Region / profile badges ──────────────────────────────────────────────────
syntax match AwsEc2Badge       /\[region:[^\]]*\]/
syntax match AwsEc2Badge       /\[profile:[^\]]*\]/

" ── Section headers ───────────────────────────────────────────────────────────
syntax match AwsEc2Section     /^General$/
syntax match AwsEc2Section     /^Placement$/
syntax match AwsEc2Section     /^Networking$/
syntax match AwsEc2Section     /^Security Groups$/
syntax match AwsEc2Section     /^Storage$/
syntax match AwsEc2Section     /^IAM Instance Profile$/
syntax match AwsEc2Section     /^Monitoring & Metadata$/
syntax match AwsEc2Section     /^Tags ([0-9]\+)$/

" ── Column header (list buffer) ───────────────────────────────────────────────
syntax match AwsEc2ColHeader   /^Instance ID\s\+Name\s\+.*/

" ── Instance IDs ──────────────────────────────────────────────────────────────
syntax match AwsEc2InstanceId  /\<i-[0-9a-f]\{8,17\}\>/

" ── AMI IDs ───────────────────────────────────────────────────────────────────
syntax match AwsEc2AmiId       /\<ami-[0-9a-f]\{8,17\}\>/

" ── Volume IDs ────────────────────────────────────────────────────────────────
syntax match AwsEc2VolumeId    /\<vol-[0-9a-f]\{8,17\}\>/

" ── Security Group IDs ────────────────────────────────────────────────────────
syntax match AwsEc2SgId        /\<sg-[0-9a-f]\{8,17\}\>/

" ── VPC / Subnet IDs ──────────────────────────────────────────────────────────
syntax match AwsEc2VpcId       /\<vpc-[0-9a-f]\{8,17\}\>/
syntax match AwsEc2SubnetId    /\<subnet-[0-9a-f]\{8,17\}\>/

" ── ENI IDs ───────────────────────────────────────────────────────────────────
syntax match AwsEc2EniId       /\<eni-[0-9a-f]\{8,17\}\>/

" ── ARNs ──────────────────────────────────────────────────────────────────────
syntax match AwsEc2Arn         /arn:aws[^ ]*/

" ── Instance states ───────────────────────────────────────────────────────────
syntax match AwsEc2StateRun    /\<running\>/
syntax match AwsEc2StateStp    /\<stopped\>/
syntax match AwsEc2StateStop   /\<stopping\>/
syntax match AwsEc2StateTerm   /\<terminated\>/
syntax match AwsEc2StatePend   /\<pending\>/
syntax match AwsEc2StateShut   /\<shutting-down\>/

" ── Instance types (e.g. t3.micro, m5.large, c6i.2xlarge) ───────────────────
syntax match AwsEc2Type        /\<[a-z][0-9a-z]\{1,4\}\.[a-z0-9]\+\>/

" ── IPv4 addresses ────────────────────────────────────────────────────────────
syntax match AwsEc2Ip          /\<\d\{1,3\}\.\d\{1,3\}\.\d\{1,3\}\.\d\{1,3\}\>/

" ── ISO dates ─────────────────────────────────────────────────────────────────
syntax match AwsEc2Date        /\d\{4}-\d\{2}-\d\{2}/

" ── Highlight links ──────────────────────────────────────────────────────────
highlight default link AwsEc2Sep         Comment
highlight default link AwsEc2Title       Title
highlight default link AwsEc2Filter      WarningMsg
highlight default link AwsEc2Loading     WarningMsg
highlight default link AwsEc2Badge       SpecialComment
highlight default link AwsEc2Section     Statement
highlight default link AwsEc2ColHeader   Normal
highlight default link AwsEc2InstanceId  Identifier
highlight default link AwsEc2AmiId       Constant
highlight default link AwsEc2VolumeId    Constant
highlight default link AwsEc2SgId        PreProc
highlight default link AwsEc2VpcId       PreProc
highlight default link AwsEc2SubnetId    PreProc
highlight default link AwsEc2EniId       PreProc
highlight default link AwsEc2Arn         Comment
highlight default link AwsEc2StateRun    DiagnosticOk
highlight default link AwsEc2StateStp    WarningMsg
highlight default link AwsEc2StateStop   WarningMsg
highlight default link AwsEc2StateTerm   Comment
highlight default link AwsEc2StatePend   WarningMsg
highlight default link AwsEc2StateShut   WarningMsg
highlight default link AwsEc2Type        Type
highlight default link AwsEc2Ip          Number
highlight default link AwsEc2Date        Constant

let b:current_syntax = "aws-ec2"
