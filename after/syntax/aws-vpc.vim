" aws.nvim – syntax highlighting for the aws-vpc filetype
syntax clear


" ── Separators ───────────────────────────────────────────────────────────────
syntax match AwsVpcSep         /^-\+$/

" ── Titles ───────────────────────────────────────────────────────────────────
syntax match AwsVpcTitle       /^VPC:.*/
syntax match AwsVpcTitle       /^VPC  .*/
syntax match AwsVpcTitle       /^Security Group:.*/
syntax match AwsVpcTitle       /^Subnet:.*/
syntax match AwsVpcTitle       /^NAT Gateway:.*/
syntax match AwsVpcTitle       /^Route Table:.*/

" ── Filter / loading badges ──────────────────────────────────────────────────
syntax match AwsVpcFilter      /\[filter:[^\]]*\]/
syntax match AwsVpcLoading     /\[loading[^\]]*\]/

" ── Region / profile badges ──────────────────────────────────────────────────
syntax match AwsVpcBadge       /\[region:[^\]]*\]/
syntax match AwsVpcBadge       /\[profile:[^\]]*\]/

" ── Section headers ───────────────────────────────────────────────────────────
syntax match AwsVpcSection     /^General$/
syntax match AwsVpcSection     /^General \/ Tags$/
syntax match AwsVpcSection     /^Tags$/
syntax match AwsVpcSection     /^Subnets$/
syntax match AwsVpcSection     /^Internet Gateways$/
syntax match AwsVpcSection     /^NAT Gateways$/
syntax match AwsVpcSection     /^Route Tables$/
syntax match AwsVpcSection     /^Routes$/
syntax match AwsVpcSection     /^Subnet Associations$/
syntax match AwsVpcSection     /^Security Groups$/
syntax match AwsVpcSection     /^Inbound Rules$/
syntax match AwsVpcSection     /^Outbound Rules$/
syntax match AwsVpcSection     /^Name\s\+VPC ID.*/

" ── Column headers ───────────────────────────────────────────────────────────
syntax match AwsVpcColHeader   /^\s\+Name\s\+Subnet ID.*/
syntax match AwsVpcColHeader   /^\s\+Group ID\s\+Name.*/

" ── Menu entry lines  (  N.  Label                    Description …)  ─────────
" Match the entire menu entry line as a region so sub-matches can be scoped
" and broad keyword patterns (available, pending, active …) are excluded.
syntax region AwsVpcMenuLine
      \ start=/^\s\+\d\+\.\s/
      \ end=/$/
      \ keepend oneline
      \ contains=AwsVpcMenuNum,AwsVpcMenuLabel,AwsVpcMenuDesc

" Number+dot prefix: leading whitespace + digit(s) + dot + whitespace
syntax match AwsVpcMenuNum   /^\s\+\d\+\.\s\+/        contained

" Label: the 22-char left-padded field after the number prefix.
" We match from after the number/whitespace up to the double-space gap.
syntax match AwsVpcMenuLabel /[A-Za-z][A-Za-z /]\+\ze\s\{2,}/  contained

" Description: everything after the double-space gap following the label.
syntax match AwsVpcMenuDesc  /\S.*$/                   contained

" ── VPC / subnet state keywords (excluded from menu lines) ───────────────────
syntax match AwsVpcAvailable   /\<available\>/   containedin=ALLBUT,AwsVpcMenuLine,AwsVpcMenuDesc
syntax match AwsVpcPending     /\<pending\>/     containedin=ALLBUT,AwsVpcMenuLine,AwsVpcMenuDesc
syntax match AwsVpcDeleting    /\<deleting\>/    containedin=ALLBUT,AwsVpcMenuLine,AwsVpcMenuDesc
syntax match AwsVpcDeleted     /\<deleted\>/     containedin=ALLBUT,AwsVpcMenuLine,AwsVpcMenuDesc

" ── NAT gateway states ────────────────────────────────────────────────────────
syntax match AwsVpcNatActive   /\bstate: available\b/
syntax match AwsVpcNatPending  /\bstate: pending\b/
syntax match AwsVpcNatFailed   /\bstate: failed\b/

" ── Route state (excluded from menu lines) ────────────────────────────────────
syntax match AwsVpcRouteActive /\<active\>/      containedin=ALLBUT,AwsVpcMenuLine,AwsVpcMenuDesc
syntax match AwsVpcRouteBlack  /\<blackhole\>/

" ── Resource IDs ──────────────────────────────────────────────────────────────
syntax match AwsVpcId          /\bvpc-[0-9a-f]\+\b/
syntax match AwsVpcSubnetId    /\bsubnet-[0-9a-f]\+\b/
syntax match AwsVpcIgwId       /\bigw-[0-9a-f]\+\b/
syntax match AwsVpcNatId       /\bnat-[0-9a-f]\+\b/
syntax match AwsVpcRtbId       /\brtb-[0-9a-f]\+\b/
syntax match AwsVpcSgId        /\bsg-[0-9a-f]\+\b/

" ── CIDR blocks ───────────────────────────────────────────────────────────────
syntax match AwsVpcCidr        /\b\d\+\.\d\+\.\d\+\.\d\+\/\d\+\b/

" ── IP addresses ──────────────────────────────────────────────────────────────
syntax match AwsVpcIp          /\b\d\+\.\d\+\.\d\+\.\d\+\b/

" ── ARNs ──────────────────────────────────────────────────────────────────────
syntax match AwsVpcArn         /arn:aws[^ ]*/

" ── Highlight links ──────────────────────────────────────────────────────────
highlight default link AwsVpcSep        Comment
highlight default link AwsVpcTitle      Title
highlight default link AwsVpcFilter     WarningMsg
highlight default link AwsVpcLoading    WarningMsg
highlight default link AwsVpcBadge      SpecialComment
highlight default link AwsVpcSection    Statement
highlight default link AwsVpcColHeader  Normal
highlight default link AwsVpcMenuLine   Normal
highlight default link AwsVpcMenuNum    Comment
highlight default link AwsVpcMenuLabel  Function
highlight default link AwsVpcMenuDesc   Comment
highlight default link AwsVpcAvailable  DiagnosticOk
highlight default link AwsVpcPending    WarningMsg
highlight default link AwsVpcDeleting   WarningMsg
highlight default link AwsVpcDeleted    Comment
highlight default link AwsVpcNatActive  DiagnosticOk
highlight default link AwsVpcNatPending WarningMsg
highlight default link AwsVpcNatFailed  DiagnosticError
highlight default link AwsVpcRouteActive DiagnosticOk
highlight default link AwsVpcRouteBlack  DiagnosticError
highlight default link AwsVpcId         Identifier
highlight default link AwsVpcSubnetId   Identifier
highlight default link AwsVpcIgwId      Identifier
highlight default link AwsVpcNatId      Identifier
highlight default link AwsVpcRtbId      Identifier
highlight default link AwsVpcSgId       Identifier
highlight default link AwsVpcCidr       Constant
highlight default link AwsVpcIp         Number
highlight default link AwsVpcArn        Comment

let b:current_syntax = "aws-vpc"
