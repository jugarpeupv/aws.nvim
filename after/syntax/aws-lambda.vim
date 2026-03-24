" aws.nvim – syntax highlighting for the aws-lambda filetype
syntax clear

" ── Separators ───────────────────────────────────────────────────────────────
syntax match AwsLambdaSep       /^-\+$/

" ── Titles ───────────────────────────────────────────────────────────────────
syntax match AwsLambdaTitle     /^Lambda Functions.*/
syntax match AwsLambdaTitle     /^Lambda  >>.*$/

" ── Filter / loading badges ──────────────────────────────────────────────────
syntax match AwsLambdaFilter    /\[filter:[^\]]*\]/
syntax match AwsLambdaLoading   /\[loading[^\]]*\]/

" ── Region / profile badges ──────────────────────────────────────────────────
syntax match AwsLambdaBadge     /\[region:[^\]]*\]/
syntax match AwsLambdaBadge     /\[profile:[^\]]*\]/

" ── Column headers ───────────────────────────────────────────────────────────
syntax match AwsLambdaColHeader /^Name\s\+Runtime.*/
syntax match AwsLambdaColHeader /^Configuration$/
syntax match AwsLambdaColHeader /^Environment Variables$/
syntax match AwsLambdaColHeader /^Layers$/
syntax match AwsLambdaColHeader /^CloudWatch Logs$/

" ── Runtime values (e.g. python3.12, nodejs20.x) ─────────────────────────────
syntax match AwsLambdaRuntime   /\(python\|nodejs\|java\|go\|dotnet\|ruby\)[^ ]*/

" ── Memory / size values ─────────────────────────────────────────────────────
syntax match AwsLambdaSize      /\d\+\(\.\d\+\)\? \(MB\|KB\|GB\|B\)\>/
syntax match AwsLambdaSize      /\d\+ MB/

" ── Timestamps ───────────────────────────────────────────────────────────────
syntax match AwsLambdaTimestamp /\d\{4}-\d\{2}-\d\{2}T\d\{2}:\d\{2}:\d\{2}/

" ── Log group path ───────────────────────────────────────────────────────────
syntax match AwsLambdaLogGroup  /\/aws\/lambda\/[^ ]*/

" ── ARN ──────────────────────────────────────────────────────────────────────
syntax match AwsLambdaArn       /arn:aws[^ ]*/

" ── Highlight links ──────────────────────────────────────────────────────────
highlight default link AwsLambdaSep       Comment
highlight default link AwsLambdaTitle     Title
highlight default link AwsLambdaFilter    WarningMsg
highlight default link AwsLambdaLoading   WarningMsg
highlight default link AwsLambdaBadge     SpecialComment
highlight default link AwsLambdaColHeader Normal
highlight default link AwsLambdaRuntime   Identifier
highlight default link AwsLambdaSize      Constant
highlight default link AwsLambdaTimestamp Comment
highlight default link AwsLambdaLogGroup  String
highlight default link AwsLambdaArn       Comment

let b:current_syntax = "aws-lambda"
