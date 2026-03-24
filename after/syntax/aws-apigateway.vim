" aws.nvim – syntax highlighting for the aws-apigateway filetype
syntax clear

" Stop regex matching past column 120 to avoid lag when holding j/k
setlocal synmaxcol=120

" ── Separators ───────────────────────────────────────────────────────────────
syntax match AwsAgwSep         /^-\+$/

" ── Titles ───────────────────────────────────────────────────────────────────
syntax match AwsAgwTitle       /^API Gateway.*/

" ── Filter / loading badges ──────────────────────────────────────────────────
syntax match AwsAgwFilter      /\[filter:[^\]]*\]/
syntax match AwsAgwLoading     /\[loading[^\]]*\]/

" ── Region / profile badges ──────────────────────────────────────────────────
syntax match AwsAgwBadge       /\[region:[^\]]*\]/
syntax match AwsAgwBadge       /\[profile:[^\]]*\]/

" ── Section headers ──────────────────────────────────────────────────────────
syntax match AwsAgwSection     /^General$/
syntax match AwsAgwSection     /^Stages\s*(.*)/
syntax match AwsAgwSection     /^Resources\s*(.*)/
syntax match AwsAgwSection     /^Authorizers\s*(.*)/
syntax match AwsAgwSection     /^ID\s\+Name.*/

" ── Endpoint types ────────────────────────────────────────────────────────────
syntax match AwsAgwEndpoint    /\<\(REGIONAL\|EDGE\|PRIVATE\)\>/

" ── ARNs ──────────────────────────────────────────────────────────────────────
syntax match AwsAgwArn         /arn:aws[^ ]*/

" ── Highlight links ──────────────────────────────────────────────────────────
highlight default link AwsAgwSep       Comment
highlight default link AwsAgwTitle     Title
highlight default link AwsAgwFilter    WarningMsg
highlight default link AwsAgwLoading   WarningMsg
highlight default link AwsAgwBadge     SpecialComment
highlight default link AwsAgwSection   Statement
highlight default link AwsAgwEndpoint  Identifier
highlight default link AwsAgwArn       Comment

let b:current_syntax = "aws-apigateway"
